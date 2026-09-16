// wayland-sandbox-socket : crée un socket Wayland réservé à une application sandboxée.
//
// Le socket est déclaré au compositeur par le protocole wp_security_context_v1 : les
// clients qui s'y connectent sont marqués « sandboxés » (moteur, app-id) et le compositeur
// peut leur refuser les protocoles privilégiés (capture d'écran, clavier virtuel...).
// Le programme reste au premier plan : quand il se termine, le compositeur cesse
// d'accepter des connexions sur ce socket.
//
// Usage : wayland-sandbox-socket <chemin du socket> <app-id> [moteur de sandbox]
// Le socket est créé en mode 0660 : placé dans un dossier setgid, il prend le groupe du
// dossier, ce qui permet de l'ouvrir à un autre compte sans lui donner $XDG_RUNTIME_DIR.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>
#include "security-context-v1-client-protocol.h"

static struct wp_security_context_manager_v1 *manager;
static const char *socket_path;

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version)
{
    if (strcmp(interface, wp_security_context_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &wp_security_context_manager_v1_interface, 1);
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void on_signal(int sig)
{
    unlink(socket_path);
    _exit(0);
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "Usage : %s <chemin du socket> <app-id> [moteur de sandbox]\n", argv[0]);
        return 2;
    }
    socket_path = argv[1];
    const char *app_id = argv[2];
    const char *engine = argc == 4 ? argv[3] : "bubblewrap";

    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (strlen(socket_path) >= sizeof addr.sun_path) {
        fprintf(stderr, "chemin de socket trop long (%zu octets max) : %s\n", sizeof addr.sun_path - 1, socket_path);
        return 2;
    }
    strcpy(addr.sun_path, socket_path);

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "connexion au compositeur impossible (WAYLAND_DISPLAY) : %s\n", strerror(errno));
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "le compositeur ne propose pas wp_security_context_manager_v1\n");
        return 1;
    }

    int listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listen_fd < 0) {
        perror("socket");
        return 1;
    }
    unlink(socket_path);
    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        perror("bind");
        return 1;
    }
    if (chmod(socket_path, 0660) < 0 || listen(listen_fd, 128) < 0) {
        perror("chmod/listen");
        unlink(socket_path);
        return 1;
    }

    // Le compositeur surveille le bout lecture du tube : il arrête d'écouter quand le bout
    // écriture, que ce programme garde ouvert jusqu'à sa fin, est fermé.
    int close_fds[2];
    if (pipe2(close_fds, O_CLOEXEC) < 0) {
        perror("pipe2");
        unlink(socket_path);
        return 1;
    }

    struct sigaction sa = { .sa_handler = on_signal };
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);

    struct wp_security_context_v1 *context =
        wp_security_context_manager_v1_create_listener(manager, listen_fd, close_fds[0]);
    wp_security_context_v1_set_sandbox_engine(context, engine);
    wp_security_context_v1_set_app_id(context, app_id);
    wp_security_context_v1_commit(context);
    wp_security_context_v1_destroy(context);
    if (wl_display_roundtrip(display) < 0) {
        fprintf(stderr, "le compositeur a refusé le contexte de sécurité\n");
        unlink(socket_path);
        return 1;
    }
    close(listen_fd);
    close(close_fds[0]);

    printf("prêt : %s\n", socket_path);
    fflush(stdout);

    // Reste en vie tant que le compositeur tourne (la connexion échoue quand il s'arrête).
    while (wl_display_dispatch(display) != -1)
        ;
    unlink(socket_path);
    return 0;
}
