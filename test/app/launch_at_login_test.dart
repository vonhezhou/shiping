import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';

class LoginDesktop extends FakeDesktop {
  @override
  bool get supportsLaunchAtLogin => true;
  LaunchAtLoginStatus status = LaunchAtLoginStatus.disabled;
  Completer<LaunchAtLoginStatus>? pending;
  Object? failure;
  int changes = 0;
  @override
  Future<LaunchAtLoginStatus> getLaunchAtLogin() async => status;
  @override
  Future<LaunchAtLoginStatus> setLaunchAtLogin(bool enabled) async {
    changes++;
    if (failure != null) throw failure!;
    return status = pending == null
        ? (enabled ? LaunchAtLoginStatus.enabled : LaunchAtLoginStatus.disabled)
        : await pending!.future;
  }
}

void main() {
  test('读取系统登录项，等待批准不误报为已启用，拒绝重复提交且不保存本地副本', () async {
    final desktop = LoginDesktop()..status = LaunchAtLoginStatus.enabled;
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.launchAtLoginStatus, LaunchAtLoginStatus.enabled);
    desktop.pending = Completer();
    final update = controller.setLaunchAtLogin(true);
    await controller.setLaunchAtLogin(false);
    expect(desktop.changes, 1);
    expect(controller.savingLaunchAtLogin, true);
    desktop.pending!.complete(LaunchAtLoginStatus.requiresApproval);
    await update;
    expect(
      controller.launchAtLoginStatus,
      LaunchAtLoginStatus.requiresApproval,
    );
    expect(controller.savingLaunchAtLogin, false);
    expect(desktop.saved, isNull);
  });

  test('注册失败保留系统状态并显示错误，刷新读取系统外部变更', () async {
    final desktop = LoginDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    desktop.failure = PlatformException(code: 'login_item_failed');
    await controller.setLaunchAtLogin(true);
    expect(controller.launchAtLoginStatus, LaunchAtLoginStatus.disabled);
    expect(controller.error, isNotNull);
    expect(controller.savingLaunchAtLogin, false);
    desktop.status = LaunchAtLoginStatus.enabled;
    await controller.refreshLaunchAtLogin();
    expect(controller.launchAtLoginStatus, LaunchAtLoginStatus.enabled);
  });
}
