/*
 * logic.h / logic.c
 *
 * the logic for the three feature functions
 */

#ifndef OVERLAYFS_TOOLS_LOGIC_H
#define OVERLAYFS_TOOLS_LOGIC_H

#include <stdbool.h>

extern bool verbose;
extern bool brief;

/*
 * feature function. will take very long time to complete. returns 0 on success
 */
int vacuum(const char* lowerdir, const char* upperdir, FILE* script_stream);

/*
 * feature function. will take very long time to complete. returns 0 on success
 */
int diff(const char* lowerdir, const char* upperdir);

/*
 * feature function. will take very long time to complete. returns 0 on success
 */
int merge(const char* lowerdir, const char* upperdir, FILE* script_stream);

/*
 * Unfold metacopy and redirect upper.
 *
 * mountdir is required and lowerdir is irrelevant.
 */
int deref(const char* mountdir, const char* upperdir, FILE* script_stream);

#endif //OVERLAYFS_TOOLS_LOGIC_H
