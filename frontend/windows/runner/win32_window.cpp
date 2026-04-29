#include "win32_window.h"
#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")

Win32Window::Win32Window() {}

Win32Window::~Win32Window() {}

bool Win32Window::Create(const wchar_t* window_title, const Point& origin,
                         const Size& size) {
  HWND window_handle =
      CreateWindowExW(WS_EX_TOPMOST, L"FLUTTER_RUNNER_WIN32_WINDOW",
                      window_title, WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                      origin.x, origin.y, size.width, size.height,
                      nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (!window_handle) {
    return false;
  }
  window_handle_ = window_handle;
  return true;
}

void Win32Window::Show() {
  ShowWindow(window_handle_, SW_SHOW);
  UpdateWindow(window_handle_);
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

HWND Win32Window::GetHandle() { return window_handle_; }

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept {
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
