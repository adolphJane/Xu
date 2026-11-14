import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/updates.dart';

void main() {
  test('selects newest release with matching asset and digest', () {
    Map<String, dynamic> release(String version, {bool valid = true}) {
      final tag = 'v$version';
      return {
        'tag_name': tag,
        'html_url': 'https://github.com/adolphJane/Xu/releases/tag/$tag',
        'draft': false,
        'assets': [
          {
            'name': 'Xu-$tag.dmg',
            'browser_download_url': valid
                ? 'https://github.com/adolphJane/Xu/releases/download/$tag/Xu-$tag.dmg'
                : 'https://other.example/file',
            'digest': 'sha256:${'a' * 64}',
          },
        ],
      };
    }

    final selected = UpdateService.select([
      release('0.6.0'),
      release('0.9.0', valid: false),
      release('0.7.0'),
    ], '0.5.2');
    expect(selected?.version, '0.7.0');
    expect(UpdateService.select([release('0.5.2')], '0.5.2'), isNull);
  });
}
