#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <memory>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();
  bool Create(const wchar_t* window_title, const Point& origin,
              const Size& size);
  void Show();
  void SetQuitOnClose(bool quit_on_close);

 protected:
  virtual void OnCreate() {}
  virtual void OnDestroy() {}
  HWND GetHandle();

 private:
  HWND window_handle_ = nullptr;
  bool quit_on_close_ = false;

  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam, LPARAM const lparam);
};

#endif  // RUNNER_WIN32_WINDOW_H_
