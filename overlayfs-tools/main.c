/*
 * main.c
 *
 * the command line user interface
 */
#define _GNU_SOURCE
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <linux/limits.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <errno.h>
#ifndef _SYS_STAT_H
  #include <linux/stat.h>
#endif
#include "logic.h"
#include "sh.h"

#define STRING_BUFFER_SIZE PATH_MAX * 2

// currently, brief and verbose are mutually exclusive
bool verbose;
bool brief;
bool yes;

void print_help(const char *program) {
    printf("Usage: %s command options\n", program);
    puts("");
    puts("Commands:");
    puts("  vacuum - remove duplicated files in upperdir where copy_up is done but the file is not actually modified");
    puts("  diff   - show the list of actually changed files");
    puts("  merge  - merge all changes from upperdir to lowerdir, and clear upperdir");
    puts("  deref  - copy changes from upperdir to a new upperdir unfolding redirect and metacopy");
    puts("");
    puts("Options:");
    puts("  -l, --lowerdir=LOWERDIR    the lowerdir of OverlayFS (required)");
    puts("  -u, --upperdir=UPPERDIR    the upperdir of OverlayFS (required)");
    puts("  -m, --mountdir=MOUNTDIR    the mountdir of OverlayFS (optional)");
    puts("  -L, --lowernew=LOWERNEW    the lowerdir of new OverlayFS (optional)");
    puts("  -U, --uppernew=UPPERNEW    the upperdir of new OverlayFS (optional)");
    puts("  -y  --yes                  don't prompt if OverlayFS is still mounted (optional)");
    puts("  -v, --verbose              with diff action only: when a directory only exists in one version, still list every file of the directory");
    puts("  -b, --brief                with diff action only: conform to output of diff --brief --recursive --no-dereference");
    puts("  -h, --help                 show this help text");
    puts("");
    puts("See https://github.com/kmxz/overlayfs-tools/ for warnings and more information.");
}

bool starts_with(const char *haystack, const char* needle) {
    return strncmp(needle, haystack, strlen(needle)) == 0;
}

bool is_mounted(const char *lower, const char *upper) {
    FILE *f = fopen("/proc/mounts", "r");
    if (!f) {
        fprintf(stderr, "Cannot read /proc/mounts to test whether OverlayFS is mounted.\n");
        return true;
    }
    char buf[STRING_BUFFER_SIZE];
    while (fgets(buf, STRING_BUFFER_SIZE, f)) {
        if (!starts_with(buf, "overlay")) {
            continue;
        }
        if (strlen(buf) == STRING_BUFFER_SIZE) {
            fprintf(stderr, "OverlayFS line in /proc/mounts is too long.\n");
            return true;
        }
        char *m_lower = strstr(buf, "lowerdir=");
        char *m_upper = strstr(buf, "upperdir=");
        if (m_lower == NULL || m_upper == NULL) {
            fprintf(stderr, "Cannot extract information from OverlayFS line in /proc/mounts.\n");
            return true;
        }
        m_lower = &(m_lower[strlen("lowerdir=")]);
        m_upper = &(m_upper[strlen("upperdir=")]);
        if (!(strncmp(lower, m_lower, strlen(lower)) && strncmp(upper, m_upper, strlen(upper)))) {
            printf("The OverlayFS involved is still mounted.\n");
            return true;
        }
    }
    return false;
}

bool check_mounted(const char *lower, const char *upper) {
    if (is_mounted(lower, upper) && !yes) {
        printf("It is strongly recommended to unmount OverlayFS first. Still continue (not recommended)?: \n");
        int r = getchar();
        if (r != 'Y' && r != 'y') {
            return true;
        }
    }
    return false;
}

bool directory_exists(const char *path) {
    struct stat sb;
    if (lstat(path, &sb) != 0) { return false; }
    return (sb.st_mode & S_IFMT) == S_IFDIR;
}

bool directory_create(const char *name, const char *path) {
    if (mkdir(path, 0755) == 0 || errno == EEXIST) { return true; }
    fprintf(stderr, "%s directory '%s' does not exist and cannot be created.\n", name, path);
    exit(EXIT_FAILURE);
}

bool real_check_xattr_trusted(const char *tmp_path, int tmp_file) {
    int ret = fsetxattr(tmp_file, "trusted.overlay.test", "naive", 5, 0);
    close(tmp_file);
    if (ret) { return false; }
    char verify_buffer[10];
    if (getxattr(tmp_path, "trusted.overlay.test", verify_buffer, 10) != 5) { return false; }
    return !strncmp(verify_buffer, "naive", 5);
}

bool check_xattr_trusted(const char *upper) {
    char tmp_path[PATH_MAX];
    strcpy(tmp_path, upper);
    strcat(tmp_path, "/.xattr_test_XXXXXX.tmp");
    int tmp_file = mkstemps(tmp_path, 4);
    if (tmp_file < 0) { return false; }
    bool ret = real_check_xattr_trusted(tmp_path, tmp_file);
    unlink(tmp_path);
    return ret;
}

int main(int argc, char *argv[]) {

    char *lower = NULL;
    char *upper = NULL;
    char *dir, *mnt = NULL;

    static struct option long_options[] = {
        { "lowerdir", required_argument, 0, 'l' },
        { "upperdir", required_argument, 0, 'u' },
        { "mountdir", required_argument, 0, 'm' },
        { "lowernew", required_argument, 0, 'L' },
        { "uppernew", required_argument, 0, 'U' },
        { "yes",      no_argument      , 0, 'y' },
        { "help",     no_argument      , 0, 'h' },
        { "verbose",  no_argument      , 0, 'v' },
        { "brief",    no_argument      , 0, 'b' },
        { 0,          0,                 0,  0  }
    };

    int opt = 0;
    int long_index = 0;
    while ((opt = getopt_long_only(argc, argv, "l:u:m:L:U:yhvb", long_options, &long_index)) != -1) {
        switch (opt) {
            case 'l':
                lower = realpath(optarg, NULL);
                if (lower) { vars[LOWERDIR] = lower; }
                break;
            case 'u':
                upper = realpath(optarg, NULL);
                if (upper) { vars[UPPERDIR] = upper; }
                break;
            case 'm':
                mnt = realpath(optarg, NULL);
                if (mnt) { vars[MOUNTDIR] = mnt; }
                break;
            case 'L':
                directory_create("New lowerdir", optarg);
                dir = realpath(optarg, NULL);
                if (dir) { vars[LOWERNEW] = dir; }
                break;
            case 'U':
                directory_create("New upperdir", optarg);
                dir = realpath(optarg, NULL);
                if (dir) { vars[UPPERNEW] = dir; }
                break;
            case 'y':
                yes = true;
                break;
            case 'h':
                print_help(argv[0]);
                return EXIT_SUCCESS;
            case 'v':
                verbose = true;
                brief = false;
                break;
            case 'b':
                verbose = false;
                brief = true;
                break;
            default:
                fprintf(stderr, "Option %c is not supported.\n", opt);
                goto see_help;
        }
    }

    if (!lower) {
        fprintf(stderr, "Lower directory not specified.\n");
        goto see_help;
    }
    if (!directory_exists(lower)) {
        fprintf(stderr, "Lower directory cannot be opened.\n");
        goto see_help;
    }
    if (!upper) {
        fprintf(stderr, "Upper directory not specified.\n");
        goto see_help;
    }
    if (!directory_exists(upper)) {
        fprintf(stderr, "Upper directory cannot be opened.\n");
        goto see_help;
    }
    if (!check_xattr_trusted(upper)) {
        fprintf(stderr, "The program cannot write trusted.* xattr. Try run again as root.\n");
        return EXIT_FAILURE;
    }
    // Relax check for mounted overlay if we are not going to modify lowerdir/upperdir
    if ((!vars[LOWERNEW] || !vars[UPPERNEW]) && check_mounted(lower, upper)) {
        return EXIT_FAILURE;
    }

    if (optind == argc - 1) {
        int out;
        char filename_template[] = "overlay-tools-XXXXXX.sh";
        FILE *script = NULL;
        if (strcmp(argv[optind], "diff") == 0) {
            out = diff(lower, upper);
        } else if (strcmp(argv[optind], "vacuum") == 0) {
            script = create_shell_script(filename_template);
            if (script == NULL) { fprintf(stderr, "Script file cannot be created.\n"); return EXIT_FAILURE; }
            out = vacuum(lower, upper, script);
        } else if (strcmp(argv[optind], "merge") == 0) {
            script = create_shell_script(filename_template);
            if (script == NULL) { fprintf(stderr, "Script file cannot be created.\n"); return EXIT_FAILURE; }
            out = merge(lower, upper, script);
        } else if (strcmp(argv[optind], "deref") == 0) {
            if (!mnt || !vars[UPPERNEW]) { fprintf(stderr, "'deref' command requires --uppernew and --mountdir.\n"); return EXIT_FAILURE; }
            if (!directory_exists(mnt)) {
                fprintf(stderr, "OverlayFS mount directory cannot be opened.\n");
                goto see_help;
            }
            script = create_shell_script(filename_template);
            if (script == NULL) { fprintf(stderr, "Script file cannot be created.\n"); return EXIT_FAILURE; }
            out = deref(mnt, upper, script);
        } else {
            fprintf(stderr, "Action not supported.\n");
            goto see_help;
        }
        if (script != NULL) {
            printf("The script %s is created. Run the script to do the actual work please. Remember to run it when the OverlayFS is not mounted.\n", filename_template);
            fclose(script);
        }
        if (out) {
            fprintf(stderr, "Action aborted due to fatal error.\n");
            return EXIT_FAILURE;
        }
        return EXIT_SUCCESS;
    }

    fprintf(stderr, "Please specify one action.\n");

see_help:
    fprintf(stderr, "Try '%s --help' for more information.\n", argv[0]);
    return EXIT_FAILURE;

}
