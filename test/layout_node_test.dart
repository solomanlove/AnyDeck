import 'package:any_deck/core/layout_inspector/layout_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseLayoutXml builds tree and unescapes node attributes', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<hierarchy rotation="0">
  <node index="0" text="A &amp; B" class="android.widget.TextView" bounds="[0,0][100,80]" />
  <node index="1" content-desc="保存&quot;按钮&quot;" class="android.widget.Button" bounds="[0,80][100,160]" />
</hierarchy>
''';

    final root = parseLayoutXml(xml);

    expect(root, isNotNull);
    expect(root!.children, hasLength(2));
    expect(root.children[0].text, 'A & B');
    expect(root.children[1].contentDesc, '保存"按钮"');
  });

  test('LayoutNode.rect supports negative bounds from clipped nodes', () {
    final node = LayoutNode({'bounds': '[-10,0][1080,2400]'});

    final rect = node.rect;

    expect(rect, isNotNull);
    expect(rect!.left, -10);
    expect(rect.top, 0);
    expect(rect.right, 1080);
    expect(rect.bottom, 2400);
  });
}
