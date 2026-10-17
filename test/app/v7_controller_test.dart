import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import '../fake_desktop.dart';
import 'v6_controller_test.dart' show ProjectFixtureCodec;

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeDesktop d;
  late AppController c;
  final bytes = File('test/fixtures/workspace.png').readAsBytesSync();
  AppController controller(FakeDesktop service) =>
      AppController(service, imageCodec: ProjectFixtureCodec());
  setUp(() async {
    d = FakeDesktop();
    c = controller(d);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await d.input.close();
  });
  Future<void> image() => c.loadImage(ImageFileData('fixture.png', bytes));
  Future<void> pin() async {
    c.useImageTool('rectangle');
    c.imageEvent('pointer', {'x': 20.0, 'y': 30.0, 'phase': 'down'});
    c.imageEvent('pointer', {'x': 80.0, 'y': 90.0, 'phase': 'up'});
    await tick();
  }

  Future<void> restart() async {
    c.dispose();
    c = controller(d);
    await c.initialize();
  }

  test('首次保存选择文件，后续写回原路径，另存为取消保留原位置', () async {
    await image();
    await pin();
    expect(await c.saveImageProject(), true);
    expect(d.savedProjectPath, null);
    expect(c.imageProjectPath, '/tmp/saved.fruler');
    expect(c.imageProjectName, 'saved.fruler');
    await c.saveImageProject();
    expect(d.savedProjectPath, '/tmp/saved.fruler');
    d.fileResult = false;
    expect(await c.saveImageProject(saveAs: true), false);
    expect(d.savedProjectPath, null);
    expect(c.imageProjectPath, '/tmp/saved.fruler');
    d.fileResult = true;
    d.saveLocation = const ProjectLocation('copy.fruler', '/tmp/copy.fruler');
    await c.saveImageProject(saveAs: true);
    expect(c.imageProjectPath, '/tmp/copy.fruler');
    expect(c.recentImageProjects.map((e) => e.path), [
      '/tmp/copy.fruler',
      '/tmp/saved.fruler',
    ]);
    await c.saveImageProject();
    expect(c.recentImageProjects.length, 2);
  });
  test('最近项目路径读取与已移动文件采用平台返回的新位置', () async {
    await image();
    await c.saveImageProject();
    await c.closeImage();
    d.projectFile = ImageProjectFileData(
      'moved.fruler',
      d.projectText!,
      path: '/tmp/moved.fruler',
    );
    await c.openImageProject(path: '/tmp/saved.fruler');
    expect(d.openedProjectPath, '/tmp/saved.fruler');
    expect(c.imageProjectPath, '/tmp/moved.fruler');
    expect(c.imageProjectDirty, false);
  });
  test('独立草稿可跨控制器恢复原图标注视图，且不重复历史', () async {
    await image();
    await pin();
    await c.saveImageProject();
    c.imageEvent('editPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('nudge', {'dx': 1, 'dy': 0});
    c.updateImageView(
      const ImageProjectView(scale: 2, x: 9, y: -12, pan: true),
    );
    final original = d.projectText;
    expect(await c.flushImageDraft(), true);
    expect(d.projectText, original);
    await restart();
    expect(c.recoveryPending, true);
    expect(c.imageDocument, null);
    await c.restoreImageDraft();
    expect(c.recoveryPending, false);
    expect(c.imageProjectPath, '/tmp/saved.fruler');
    expect(c.imageProjectDirty, true);
    expect((c.imageOverlay['pinned'] as List).single['rect']['left'], 21);
    expect(c.imageView!.scale, 2);
    expect(c.imageView!.pan, true);
    expect(c.measurements.length, 1);
    expect(c.imageOverlay['canUndoPins'], false);
    await c.saveImageProject();
    expect(d.savedProjectPath, '/tmp/saved.fruler');
  });
  test('已保存项目的正常退出也写独立草稿，重启恢复仍是已保存', () async {
    await image();
    await c.saveImageProject();
    d.event('quitRequested');
    await tick();
    await tick();
    expect(d.quitAllowed, true);
    expect(d.draft, isNotNull);
    await restart();
    await c.restoreImageDraft();
    expect(c.imageProjectDirty, false);
    expect(c.imageProjectName, 'saved.fruler');
  });
  test('取消退出保留草稿，明确放弃退出才清除，关闭文档清除草稿', () async {
    await image();
    await c.flushImageDraft();
    c.confirmImageReplacement = () async => false;
    d.event('quitRequested');
    await tick();
    expect(d.quitAllowed, false);
    expect(d.draft, isNotNull);
    c.confirmImageReplacement = () async => true;
    d.event('quitRequested');
    await tick();
    await tick();
    expect(d.quitAllowed, true);
    expect(d.draft, null);
    await c.flushImageDraft();
    await c.closeImage();
    expect(d.draft, null);
    expect(c.imageDocument, null);
  });
  test('损坏草稿保留，恢复失败不会清空，可主动丢弃', () async {
    d.draft = '{bad';
    await restart();
    await c.restoreImageDraft();
    expect(c.recoveryPending, true);
    expect(d.draft, '{bad');
    expect(c.imageDocument, null);
    expect(c.error, contains('无法恢复'));
    await image();
    expect(c.imageDocument, null);
    await c.discardRecovery();
    expect(c.recoveryPending, false);
    expect(d.draft, null);
  });
  test('恢复选择前挂起外部项目，丢弃后打开，未保存恢复文档仍需确认替换', () async {
    await image();
    await c.saveImageProject();
    final file = ImageProjectFileData(
      'external.fruler',
      d.projectText!,
      path: '/tmp/external.fruler',
    );
    c.updateImageView(const ImageProjectView(scale: 2, x: 0, y: 0));
    await c.flushImageDraft();
    await restart();
    d.projectFile = file;
    d.event('openProject', {'path': '/tmp/external.fruler'});
    await tick();
    expect(c.imageDocument, null);
    c.confirmImageReplacement = () async => false;
    await c.restoreImageDraft();
    await tick();
    expect(c.imageProjectName, 'saved.fruler');
    expect(c.imageView!.scale, 2);
    expect(c.imageProjectDirty, true);
  });
  test('草稿磁盘失败可重试，未写原文件；丢弃与在途写入严格串行', () async {
    await image();
    d.draftError = StateError('disk');
    expect(await c.flushImageDraft(), false);
    expect(c.draftError, contains('草稿保存失败'));
    expect(d.projectText, null);
    d.draftError = null;
    d.pendingDraftSave = Completer<void>();
    final saving = c.flushImageDraft();
    await tick();
    final closing = c.closeImage();
    await tick();
    d.pendingDraftSave!.complete();
    await saving;
    await closing;
    expect(d.draftWrites.last, null);
    expect(d.draft, null);
  });
  test('恢复入口不解析或执行路径权限，原文件失效保存失败仍保留未保存内容', () async {
    await image();
    await c.saveImageProject();
    c.updateImageView(const ImageProjectView(scale: 2, x: 0, y: 0));
    d.projectError = StateError('permission');
    expect(await c.saveImageProject(), false);
    expect(c.imageProjectDirty, true);
    expect(c.imageProjectPath, '/tmp/saved.fruler');
    expect(c.error, contains('另存为'));
    await c.flushImageDraft();
    final data = jsonDecode(d.draft!) as Map;
    expect(data['location']['path'], '/tmp/saved.fruler');
    expect(data['dirty'], true);
  });
  test('保留草稿退出可正常重启继续未命名工作，不触发原文件保存', () async {
    await image();
    await pin();
    c.confirmImageQuit = c.keepImageDraftForQuit;
    d.event('quitRequested');
    await tick();
    await tick();
    expect(d.quitAllowed, true);
    expect(d.draft, isNotNull);
    expect(d.projectText, null);
    await restart();
    await c.restoreImageDraft();
    expect(c.imageProjectDirty, true);
    expect(c.imageProjectPath, null);
    expect((c.imageOverlay['pinned'] as List).length, 1);
  });
  test('草稿读取失败保护原文件，可重试恢复或主动丢弃，不允许自动覆盖', () async {
    await image();
    await c.flushImageDraft();
    final old = d.draft;
    d.draftReadError = StateError('unreadable');
    await restart();
    expect(c.recoveryPending, true);
    await image();
    expect(c.imageDocument, null);
    await c.flushImageDraft();
    expect(d.draft, old);
    await c.restoreImageDraft();
    expect(c.recoveryPending, true);
    d.draftReadError = null;
    await c.restoreImageDraft();
    expect(c.imageDocument, isNotNull);
    expect(c.recoveryPending, false);
  });
  test('外部打开请求在保存完成后处理，不因保存面板占用而丢失', () async {
    await image();
    await c.saveImageProject();
    d.projectFile = ImageProjectFileData(
      'incoming.fruler',
      d.projectText!,
      path: '/tmp/incoming.fruler',
    );
    d.pendingProjectSave = Completer<bool>();
    final saving = c.saveImageProject();
    await tick();
    d.event('openProject', {'path': '/tmp/incoming.fruler'});
    expect(c.imageProjectName, 'saved.fruler');
    d.pendingProjectSave!.complete(true);
    await saving;
    await tick();
    await tick();
    expect(c.imageProjectName, 'incoming.fruler');
    expect(d.openedProjectPath, '/tmp/incoming.fruler');
  });
}
