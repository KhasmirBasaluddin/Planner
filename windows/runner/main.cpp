#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// Must match the title passed to window.Create below — that is how a second
// process locates the first one's window.
constexpr wchar_t kWindowTitle[] = L"planner";

// Hands a `planner://` link to the already-running instance and brings it
// forward, rather than starting a second copy of the app.
//
// Returns true when an existing window was found and handled, in which case
// this process should exit immediately.
bool SendAppLinkToInstance(const std::wstring& title) {
  HWND window = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (window == nullptr) {
    return false;
  }

  // Delivers the URL from this process's command line to the running instance,
  // where the app_links plugin surfaces it on the Dart side.
  SendAppLink(window);

  // Restore the window in whatever state the user left it, then raise it.
  WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  ::GetWindowPlacement(window, &placement);
  switch (placement.showCmd) {
    case SW_SHOWMAXIMIZED:
      ::ShowWindow(window, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ::ShowWindow(window, SW_RESTORE);
      break;
    default:
      ::ShowWindow(window, SW_NORMAL);
      break;
  }
  ::SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
  ::SetForegroundWindow(window);

  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance: without this, clicking a confirmation link in an email
  // starts a second copy of the app instead of reusing the running one.
  if (SendAppLinkToInstance(kWindowTitle)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
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
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
