#ifndef OVERLAYFS_TOOLS_SH_H
#define OVERLAYFS_TOOLS_SH_H

enum {
    LOWERDIR,
    UPPERDIR,
    MOUNTDIR,
    LOWERNEW,
    UPPERNEW,
    NUM_VARS
};

extern const char *var_names[NUM_VARS];
extern char *vars[NUM_VARS];

FILE* create_shell_script(char *tmp_path_buffer);

int command(FILE *output, const char *command_format, ...);

#endif //OVERLAYFS_TOOLS_SH_H
