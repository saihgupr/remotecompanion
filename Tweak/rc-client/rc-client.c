#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

int main(int argc, char *argv[]) {
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("socket");
        return 1;
    }
    
    struct sockaddr_un serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sun_family = AF_UNIX;
    strncpy(serv_addr.sun_path, "/var/mobile/Documents/rc.sock", sizeof(serv_addr.sun_path) - 1);
    
    struct timeval tv;
    tv.tv_sec = 2;
    tv.tv_usec = 0;
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);
    
    if (connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("connect");
        return 1;
    }
    
    char buffer[1024];
    
    // Command from arguments vs stdin
    if (argc > 1) {
        // Send arguments joined by space
        size_t total_len = 0;
        for (int i = 1; i < argc; i++) total_len += strlen(argv[i]) + 1;
        char *cmd = malloc(total_len + 1);
        cmd[0] = '\0';
        for (int i = 1; i < argc; i++) {
            strcat(cmd, argv[i]);
            if (i < argc - 1) strcat(cmd, " ");
        }
        write(sockfd, cmd, strlen(cmd));
        free(cmd);
    } else {
        // Read from stdin (piping logic): all of it, so a long command isn't cut at 1 KB
        size_t bytes_read;
        while ((bytes_read = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
            if (write(sockfd, buffer, bytes_read) < 0) break;
        }
    }
    
    // Read response
    ssize_t n;
    while ((n = read(sockfd, buffer, sizeof(buffer) - 1)) > 0) {
        fwrite(buffer, 1, n, stdout);
        fflush(stdout);
    }
    if (n < 0) {
        perror("read");
    }
    
    close(sockfd);
    return 0;
}
