#include "utils.h"
#include <windows.h>
#include <shlwapi.h>

bool FileExistsAtPath(const wchar_t* path) {
  return PathFileExistsW(path);
}
