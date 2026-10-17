import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import '../fake_desktop.dart';
import 'v5_controller_test.dart' show FixtureCodec;

class ProjectFixtureCodec extends FixtureCodec {
  @override
  Future<ImageDocument> decodeProjectPng(ImageFileData file) => decode(file);
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeDesktop d;
  late AppController c;
  final bytes = File('test/fixtures/workspace.png').readAsBytesSync();
  setUp(() async {
    d = FakeDesktop();
    c = AppController(d, imageCodec: ProjectFixtureCodec());
    await c.initialize();
    await c.loadImage(ImageFileData('fixture.png', bytes));
  });
  tearDown(() async {
    c.dispose();
    await d.input.close();
  });
  Future<void> pin() async {
    c.useImageTool('rectangle');
    c.imageEvent('pointer', {'x': 20.0, 'y': 30.0, 'phase': 'down'});
    c.imageEvent('pointer', {'x': 80.0, 'y': 90.0, 'phase': 'up'});
    await tick();
  }

  List pins() => (c.imageOverlay['pinned'] as List);
  test('保存恢复图片、标注、工具和视图；恢复不新增测量历史', () async {
    await pin();
    c.updateImageView(
      const ImageProjectView(scale: 2, x: 13, y: -20, pan: true),
    );
    expect(c.imageProjectDirty, true);
    expect(await c.saveImageProject(), true);
    expect(c.imageProjectDirty, false);
    final saved = d.projectText!;
    await c.closeImage();
    expect(c.imageDocument, isNull);
    d.projectFile = ImageProjectFileData('copy.fruler', saved);
    await c.openImageProject();
    expect(c.imageDocument!.frame.width, 240);
    expect(pins().single['id'], 1);
    expect(c.imageTool, 'rectangle');
    expect(c.imageView!.x, 13);
    expect(c.imageView!.pan, true);
    expect(c.imageProjectDirty, false);
    expect(c.measurements.length, 1);
    expect(c.imageOverlay['canUndoPins'], false);
    c.imageEvent('editPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('nudge', {'dx': 1, 'dy': 0});
    expect(c.imageProjectDirty, true);
    c.imageEvent('undoPins');
    expect(c.imageProjectDirty, false);
    c.imageEvent('redoPins');
    expect(c.imageProjectDirty, true);
  });
  test('图片添加删除移动缩放清空均可撤销重做，新编辑截断重做分支', () async {
    await pin();
    c.imageEvent('editPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('deletePin');
    expect(pins(), isEmpty);
    c.imageEvent('undoPins');
    expect(pins().length, 1);
    c.imageEvent('redoPins');
    expect(pins(), isEmpty);
    c.imageEvent('undoPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('nudge', {'dx': 1, 'dy': 0, 'resize': true});
    expect(c.imageOverlay['canRedoPins'], false);
    expect(pins().single['rect']['right'], 81);
    c.imageEvent('undoPins');
    expect(pins().single['rect']['right'], 80);
    c.imageEvent('redoPins');
    expect(pins().single['rect']['right'], 81);
    c.imageEvent('clearPins');
    expect(pins(), isEmpty);
    c.imageEvent('undoPins');
    expect(pins().length, 1);
    c.imageEvent('redoPins');
    expect(pins(), isEmpty);
    expect(c.measurements.length, 1);
  });
  test('一次拖拽一次撤销重做，拖动中撤销会结束旧手势', () async {
    await pin();
    c.imageEvent('editPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('pinDrag', {'id': 1, 'phase': 'start'});
    c.imageEvent('pinDrag', {
      'id': 1,
      'phase': 'update',
      'dx': 10,
      'dy': 5,
      'handle': 'move',
    });
    c.imageEvent('undoPins');
    expect(pins().single['rect']['left'], 20);
    c.imageEvent('pinDrag', {'id': 1, 'phase': 'end', 'dx': 99, 'dy': 99});
    expect(pins().single['rect']['left'], 20);
    c.imageEvent('redoPins');
    expect(pins().single['rect']['left'], 30);
  });
  test('切换屏幕工具保留图片草稿、撤销重做和已保存状态', () async {
    await pin();
    await c.saveImageProject();
    c.imageEvent('undoPins');
    await c.startRuler();
    expect(c.busy, true);
    d.event('cancelled');
    c.selectSection(AppSection.image);
    expect(pins(), isEmpty);
    expect(c.imageOverlay['canRedoPins'], true);
    c.imageEvent('redoPins');
    expect(pins().length, 1);
    expect(c.imageProjectDirty, false);
  });
  test('保存取消失败和写入期间修改均不错误清除未保存状态', () async {
    await pin();
    d.fileResult = false;
    expect(await c.saveImageProject(), false);
    expect(c.imageProjectDirty, true);
    d.projectError = StateError('disk');
    expect(await c.saveImageProject(), false);
    expect(c.error, contains('保存失败'));
    d.projectError = null;
    d.pendingProjectSave = Completer<bool>();
    final pending = c.saveImageProject();
    await tick();
    c.updateImageView(const ImageProjectView(scale: 3, x: 0, y: 0));
    d.pendingProjectSave!.complete(true);
    await pending;
    expect(c.imageProjectDirty, true);
  });
  test('损坏项目和元数据不一致不替换当前文档', () async {
    await pin();
    final old = c.imageDocument;
    d.projectFile = const ImageProjectFileData('bad.fruler', '{}');
    await c.openImageProject();
    expect(identical(c.imageDocument, old), true);
    expect(pins().length, 1);
    d.projectFile = ImageProjectFileData(
      'bad.fruler',
      ImageProject(
        name: 'bad.png',
        png: bytes,
        width: 120,
        height: 160,
        annotations: [],
        tool: 'picker',
      ).encode(),
    );
    await c.openImageProject();
    expect(identical(c.imageDocument, old), true);
    expect(c.error, contains('不一致'));
  });
  test('未保存取消替换和关闭，退出确认反馈真实结果', () async {
    c.confirmImageReplacement = () async => false;
    final old = c.imageDocument;
    await c.loadImage(ImageFileData('new.png', bytes));
    expect(identical(c.imageDocument, old), true);
    await c.closeImage();
    expect(c.imageDocument, isNotNull);
    d.event('quitRequested');
    await tick();
    expect(d.quitAllowed, false);
    c.confirmImageReplacement = () async => true;
    d.event('quitRequested');
    await tick();
    expect(d.quitAllowed, true);
  });
  test('屏幕标注同样支持重做并且新会话清空两条历史栈', () async {
    await c.startRuler();
    d.pointer(x: 0, y: 0, phase: 'down');
    d.pointer(x: 2, y: 2, phase: 'up', keep: true);
    await tick();
    d.event('undoPins');
    expect(d.lastOverlay!['pinned'], isEmpty);
    expect(d.lastOverlay!['canRedoPins'], true);
    d.event('redoPins');
    expect((d.lastOverlay!['pinned'] as List).length, 1);
    d.event('cancelled');
    await c.startRuler();
    expect(d.lastOverlay!['canRedoPins'], false);
    expect(d.lastOverlay!['canUndoPins'], false);
  });
}
