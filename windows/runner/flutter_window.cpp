#include "flutter_window.h"

#include <optional>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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
  close_state_ = std::make_shared<CloseState>();
  close_state_->window = GetHandle();
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "tiger/window",
      &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (close_state_) { close_state_->alive = false; close_state_->window = nullptr; }
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Defer destruction until Dart finishes its save/discard dialog. A weak state
  // capture and posted message keep asynchronous replies away from a destroyed
  // window/controller and avoid nested destruction during channel dispatch.
  if (message == WM_CLOSE && window_channel_ && close_state_ &&
      !close_state_->confirmed) {
    if (close_state_->pending) return 0;
    close_state_->pending = true;
    std::weak_ptr<CloseState> weak_state = close_state_;
    window_channel_->InvokeMethod(
        "requestClose", nullptr,
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [weak_state](const flutter::EncodableValue* value) {
              const auto state = weak_state.lock();
              if (!state || !state->alive) return;
              state->pending = false;
              const bool* approved = value ? std::get_if<bool>(value) : nullptr;
              if (approved && *approved && IsWindow(state->window)) {
                state->confirmed = true;
                PostMessage(state->window, WM_CLOSE, 0, 0);
              }
            },
            [weak_state](const std::string&, const std::string&,
                         const flutter::EncodableValue*) {
              if (const auto state = weak_state.lock()) state->pending = false;
            },
            [weak_state]() {
              if (const auto state = weak_state.lock()) state->pending = false;
            }));
    return 0;
  }
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
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
