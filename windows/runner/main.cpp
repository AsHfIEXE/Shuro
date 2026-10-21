#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\Shuro.SingleInstance.v1";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"Shuro";
constexpr UINT kShowExistingWindowMessage = WM_APP + 42;

void FocusExistingWindow() {
  // The first process can own the mutex just before its native window is
  // created. Give it a short handoff window so a fast second click still
  // reaches the real window instead of silently doing nothing.
  for (int attempt = 0; attempt < 20; ++attempt) {
    HWND existing = FindWindow(kWindowClassName, kWindowTitle);
    if (existing != nullptr) {
      SendMessage(existing, kShowExistingWindowMessage, 0, 0);
      return;
    }
    Sleep(25);
  }
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  HANDLE single_instance = CreateMutex(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance == nullptr) {
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    FocusExistingWindow();
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"Shuro", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
