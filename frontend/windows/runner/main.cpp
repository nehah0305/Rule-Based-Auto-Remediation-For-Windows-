#include <windows.h>
#include <flutter/flutter_window.h>
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  flutter::FlutterWindow window(instance, L"Remediation Center");
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1400, 900);
  if (!window.CreateAndShow(L"Remediation Center", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  flutter::DartEntrypoint entrypoint{".packages", "lib/main.dart"};
  if (!window.Run(entrypoint)) {
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
