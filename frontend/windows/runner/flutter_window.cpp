#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>
#include <shellapi.h>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::string Utf8FromWideString(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }

  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

flutter::EncodableValue FilePathListFromDrop(HDROP drop) {
  flutter::EncodableList paths;
  const UINT file_count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  paths.reserve(file_count);

  for (UINT index = 0; index < file_count; ++index) {
    const UINT path_length = DragQueryFileW(drop, index, nullptr, 0);
    if (path_length == 0) {
      continue;
    }

    std::wstring path(path_length + 1, L'\0');
    DragQueryFileW(drop, index, path.data(), path_length + 1);
    path.resize(path_length);
    paths.emplace_back(Utf8FromWideString(path));
  }

  return flutter::EncodableValue(std::move(paths));
}

flutter::EncodableValue ClipboardFilePaths(HWND owner) {
  if (!OpenClipboard(owner)) {
    return flutter::EncodableValue(flutter::EncodableList());
  }

  flutter::EncodableValue result{flutter::EncodableList()};
  HANDLE clipboard_data = GetClipboardData(CF_HDROP);
  if (clipboard_data != nullptr) {
    result = FilePathListFromDrop(static_cast<HDROP>(clipboard_data));
  }

  CloseClipboard();
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  DragAcceptFiles(GetHandle(), TRUE);

  file_intake_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "harmony/file_intake",
          &flutter::StandardMethodCodec::GetInstance());
  file_intake_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "readClipboardFiles") {
          result->Success(ClipboardFilePaths(GetHandle()));
          return;
        }

        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  HWND window = GetHandle();
  if (window != nullptr) {
    DragAcceptFiles(window, FALSE);
  }
  file_intake_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_DROPFILES: {
      HDROP drop = reinterpret_cast<HDROP>(wparam);
      flutter::EncodableValue paths = FilePathListFromDrop(drop);
      DragFinish(drop);

      if (file_intake_channel_) {
        file_intake_channel_->InvokeMethod(
            "filesDropped",
            std::make_unique<flutter::EncodableValue>(std::move(paths)));
      }
      return 0;
    }

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
