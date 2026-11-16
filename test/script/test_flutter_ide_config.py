"""验证 AnyDeck IDE 修复覆盖模块宏、SDK 绑定与已有配置保留。"""
from pathlib import Path
import shlex
import sys
import tempfile
import unittest
from urllib.parse import unquote
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import configure_flutter_ide as config


class FlutterIdeConfigTests(unittest.TestCase):
    """使用独立临时工程验证修复，不修改开发者实际的 IDE 配置。"""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / 'AnyDeck'
        self.sdk = self.root / 'Flutter SDK & tools'
        for relative, content in (
            ('pubspec.yaml', 'name: any_deck\n'),
            ('lib/main.dart', 'void main() {}\n'),
        ):
            self.write(self.project / relative, content)
        for relative in ('bin/flutter', 'bin/cache/dart-sdk/bin/dart'):
            self.write(self.sdk / relative, 'fixture')
        for name in ('core', 'async', 'io'):
            (self.sdk / 'bin/cache/dart-sdk/lib' / name).mkdir(parents=True)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def snapshot(self, directory):
        return {
            str(path.relative_to(directory)): path.read_bytes()
            for path in directory.rglob('*') if path.is_file()
        }

    def test_creates_usable_flutter_project_configuration(self):
        config.configure(self.project, self.sdk)
        idea = self.project / '.idea'
        module = ET.parse(idea / 'AnyDeck.iml').getroot()
        content = module.find("./component[@name='NewModuleRootManager']/content")
        self.assertEqual(content.get('url'), 'file://$MODULE_DIR$')
        sources = {item.get('url'): item.get('isTestSource')
                   for item in content.findall('sourceFolder')}
        self.assertEqual(sources['file://$MODULE_DIR$/lib'], 'false')
        self.assertEqual(sources['file://$MODULE_DIR$/test'], 'true')
        self.assertIsNotNone(module.find("./component/orderEntry[@name='Dart SDK']"))
        modules = ET.parse(idea / 'modules.xml').getroot()
        self.assertIsNotNone(modules.find(
            ".//module[@filepath='$PROJECT_DIR$/.idea/AnyDeck.iml']"))
        run = ET.parse(idea / 'runConfigurations/AnyDeck.xml').getroot()
        flutter = run.find("./configuration[@name='AnyDeck']")
        self.assertEqual(flutter.get('type'), 'FlutterRunConfigurationType')
        self.assertEqual(flutter.find("./option[@name='filePath']").get('value'),
                         '$PROJECT_DIR$/lib/main.dart')
        self.assertEqual(flutter.find("./option[@name='additionalArgs']").get('value'),
                         '--no-pub')
        no_share = ET.parse(idea / 'runConfigurations/AnyDeck_No_Share_Core.xml').find(
            './configuration')
        self.assertEqual(no_share.get('name'), 'AnyDeck（不含 Share Core）')
        self.assertEqual(no_share.find("./option[@name='filePath']").get('value'),
                         '$PROJECT_DIR$/lib/main.dart')
        arguments = shlex.split(no_share.find("./option[@name='additionalArgs']").get('value'))
        self.assertIn('--no-pub', arguments)
        self.assertIn('--debug', arguments)
        self.assertIn('--dart-define=ANYDECK_ENABLE_SHARE_CORE=false', arguments)
        self.assertEqual(no_share.find(
            "./option[@name='envs']/entry[@key='ANYDECK_SKIP_SHARE_CORE']").get('value'), '1')

    def test_standard_module_keeps_custom_settings_and_child_modules(self):
        idea = self.project / '.idea'
        self.write(idea / 'AnyDeck.iml', '''<module type="JAVA_MODULE" version="4">
  <!-- 保留开发者自定义设置 -->
  <component name="CustomSettings"><option name="keep" value="yes" /></component>
  <component name="NewModuleRootManager" inherit-compiler-output="true">
    <content url="file://$MODULE_DIR$">
      <excludeFolder url="file://$MODULE_DIR$/build" />
    </content>
    <orderEntry type="library" name="scrcpy" level="project" />
  </component>
</module>
''')
        helper = self.project / 'tool/android_helper/android_helper.iml'
        self.write(helper, '<module><component name="KeepHelper" /></module>\n')
        modules = '''<project version="4">
  <component name="ProjectModuleManager"><modules>
    <module fileurl="file://$PROJECT_DIR$/.idea/AnyDeck.iml" filepath="$PROJECT_DIR$/.idea/AnyDeck.iml" />
    <module fileurl="file://$PROJECT_DIR$/tool/android_helper/android_helper.iml" filepath="$PROJECT_DIR$/tool/android_helper/android_helper.iml" />
  </modules></component>
</project>
'''
        self.write(idea / 'modules.xml', modules)
        config.configure(self.project, self.sdk)
        repaired = (idea / 'AnyDeck.iml').read_text()
        self.assertIn('<!-- 保留开发者自定义设置 -->', repaired)
        self.assertIn('<option name="keep" value="yes" />', repaired)
        self.assertIn('name="scrcpy"', repaired)
        self.assertNotIn('file://$PROJECT_DIR$', repaired)
        module = ET.fromstring(repaired)
        self.assertEqual(module.find('.//excludeFolder').get('url'),
                         'file://$MODULE_DIR$/build')
        self.assertEqual((idea / 'modules.xml').read_text(), modules)
        self.assertEqual(helper.read_text(),
                         '<module><component name="KeepHelper" /></module>\n')

    def test_legacy_macros_return_to_standard_module_root_idempotently(self):
        path = self.project / '.idea/AnyDeck.iml'
        for prefix in ('file://$PROJECT_DIR$', 'file://$MODULE_DIR$/..'):
            with self.subTest(prefix=prefix):
                self.write(path, f'''<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="{prefix}">
      <sourceFolder url="{prefix}/lib" isTestSource="false" />
      <sourceFolder url="{prefix}/test" isTestSource="true" />
      <excludeFolder url="{prefix}/build" />
    </content>
  </component>
</module>
''')
                config.configure(self.project, self.sdk)
                repaired = path.read_text()
                self.assertNotIn('file://$PROJECT_DIR$', repaired)
                self.assertNotIn('$MODULE_DIR$/..', repaired)
                content = ET.fromstring(repaired).find('./component/content')
                self.assertEqual(content.get('url'), 'file://$MODULE_DIR$')
                self.assertEqual(content.find('sourceFolder').get('url'),
                                 'file://$MODULE_DIR$/lib')
                self.assertEqual(content.find('excludeFolder').get('url'),
                                 'file://$MODULE_DIR$/build')
                self.assertEqual(config.configure(self.project, self.sdk), [])
                self.assertEqual(path.read_text(), repaired)

    def test_idea_module_macro_expands_to_project_root_not_parent(self):
        config.configure(self.project, self.sdk)
        module_file = self.project / '.idea/AnyDeck.iml'
        content = ET.parse(module_file).find('./component/content')
        # IntelliJ PathMacroUtil 对 .idea 下的 iml 特判，将 MODULE_DIR 定为项目根。
        module_directory = module_file.parent
        if module_directory.name == '.idea':
            module_directory = module_directory.parent
        expanded = Path(content.get('url').removeprefix('file://').replace(
            '$MODULE_DIR$', str(module_directory))).resolve()
        self.assertEqual(expanded, self.project.resolve())
        self.assertNotEqual(expanded, self.project.resolve().parent)

    def test_existing_run_arguments_environment_and_flavor_are_preserved(self):
        path = self.project / '.idea/runConfigurations/AnyDeck.xml'
        self.write(path, '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="AnyDeck" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="additionalArgs" value="--dart-define=TEST=true" />
    <option name="envs"><entry key="ANYDECK_TEST" value="keep &amp; value" /></option>
    <option name="buildFlavor" value="custom" />
    <method v="2"><option name="CustomBeforeRun" enabled="true" /></method>
  </configuration>
</component>
''')
        config.configure(self.project, self.sdk)
        run = ET.parse(path).find('./configuration')
        arguments = run.find("./option[@name='additionalArgs']").get('value').split()
        self.assertEqual(arguments, ['--dart-define=TEST=true', '--no-pub'])
        environment = run.find("./option[@name='envs']/entry")
        self.assertEqual(environment.attrib,
                         {'key': 'ANYDECK_TEST', 'value': 'keep & value'})
        self.assertEqual(run.find("./option[@name='buildFlavor']").get('value'), 'custom')
        self.assertIsNotNone(run.find("./method/option[@name='CustomBeforeRun']"))
        self.assertEqual(run.find("./option[@name='filePath']").get('value'),
                         '$PROJECT_DIR$/lib/main.dart')
        repaired = path.read_bytes()
        self.assertEqual(config.configure(self.project, self.sdk), [])
        self.assertEqual(path.read_bytes(), repaired)

    def test_no_share_entry_inherits_toolchain_without_changing_full_entry(self):
        path = self.project / '.idea/runConfigurations/AnyDeck.xml'
        original = '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="AnyDeck" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="filePath" value="$PROJECT_DIR$/lib/main.dart" />
    <option name="additionalArgs" value="--no-pub --profile --dart-define=TEST='two words' --dart-define=ANYDECK_ENABLE_SHARE_CORE=true" />
    <option name="envs"><entry key="CARGO" value="/tool chain/cargo &amp; tools" /><entry key="OTHER" value="keep" /></option>
    <option name="buildFlavor" value="custom" />
    <method v="2"><option name="CustomBeforeRun" enabled="true" /></method>
  </configuration>
</component>
'''
        self.write(path, original)
        config.configure(self.project, self.sdk)
        self.assertEqual(path.read_text(), original)
        no_share = ET.parse(path.with_name('AnyDeck_No_Share_Core.xml')).find('./configuration')
        arguments = shlex.split(no_share.find("./option[@name='additionalArgs']").get('value'))
        self.assertIn('--dart-define=TEST=two words', arguments)
        self.assertIn('--debug', arguments)
        self.assertNotIn('--profile', arguments)
        self.assertNotIn('--dart-define=ANYDECK_ENABLE_SHARE_CORE=true', arguments)
        self.assertEqual(arguments.count('--dart-define=ANYDECK_ENABLE_SHARE_CORE=false'), 1)
        environment = {entry.get('key'): entry.get('value')
                       for entry in no_share.findall("./option[@name='envs']/entry")}
        self.assertEqual(environment, {
            'CARGO': '/tool chain/cargo & tools', 'OTHER': 'keep',
            'ANYDECK_SKIP_SHARE_CORE': '1',
        })
        self.assertEqual(no_share.find("./option[@name='buildFlavor']").get('value'), 'custom')
        self.assertIsNotNone(no_share.find("./method/option[@name='CustomBeforeRun']"))

    def test_existing_no_share_entry_keeps_custom_options_and_first_backup(self):
        directory = self.project / '.idea/runConfigurations'
        full = config.RUN_CONFIG.replace(
            '    <method v="2" />',
            '    <option name="envs"><entry key="CARGO" value="base cargo" />'
            '<entry key="BASE_ONLY" value="inherited" /></option>\n    <method v="2" />')
        self.write(directory / 'AnyDeck.xml', full)
        path = directory / 'AnyDeck_No_Share_Core.xml'
        original = '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="AnyDeck local" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="filePath" value="old.dart" />
    <option name="additionalArgs" value="--release -D ANYDECK_ENABLE_SHARE_CORE=true --dart-define=LOCAL=value" />
    <option name="envs"><entry key="CARGO" value="custom cargo" /><entry key="LOCAL" value="keep" /><entry key="ANYDECK_SKIP_SHARE_CORE" value="0" /></option>
    <method v="2" />
  </configuration>
</component>
'''
        self.write(path, original)
        config.configure(self.project, self.sdk)
        no_share = ET.parse(path).find('./configuration')
        self.assertEqual(no_share.get('name'), 'AnyDeck（不含 Share Core）')
        arguments = shlex.split(no_share.find("./option[@name='additionalArgs']").get('value'))
        self.assertNotIn('--release', arguments)
        self.assertNotIn('ANYDECK_ENABLE_SHARE_CORE=true', arguments)
        self.assertIn('--dart-define=LOCAL=value', arguments)
        self.assertIn('--debug', arguments)
        self.assertIn('--no-pub', arguments)
        self.assertEqual(arguments.count('--dart-define=ANYDECK_ENABLE_SHARE_CORE=false'), 1)
        environment = {entry.get('key'): entry.get('value')
                       for entry in no_share.findall("./option[@name='envs']/entry")}
        self.assertEqual(environment, {
            'CARGO': 'custom cargo', 'LOCAL': 'keep', 'BASE_ONLY': 'inherited',
            'ANYDECK_SKIP_SHARE_CORE': '1',
        })
        backup = self.project / '.idea/.anydeck-backup/runConfigurations/AnyDeck_No_Share_Core.xml'
        self.assertEqual(backup.read_text(), original)
        before = self.snapshot(self.project / '.idea')
        self.assertEqual(config.configure(self.project, self.sdk), [])
        self.assertEqual(self.snapshot(self.project / '.idea'), before)
        self.assertEqual((directory / 'AnyDeck.xml').read_text(), full)

    def test_adds_main_module_without_losing_other_modules(self):
        path = self.project / '.idea/modules.xml'
        self.write(path, '''<project version="4">
  <component name="ProjectModuleManager"><modules>
    <module fileurl="file://$PROJECT_DIR$/tool/usage_companion/usage_companion.iml" filepath="$PROJECT_DIR$/tool/usage_companion/usage_companion.iml" />
  </modules></component>
</project>
''')
        config.configure(self.project, self.sdk)
        paths = {item.get('filepath') for item in ET.parse(path).findall('.//module')}
        self.assertEqual(paths, {
            '$PROJECT_DIR$/.idea/AnyDeck.iml',
            '$PROJECT_DIR$/tool/usage_companion/usage_companion.iml',
        })

    def test_sdk_path_with_spaces_and_ampersand_remains_valid_xml(self):
        config.configure(self.project, self.sdk)
        path = self.project / '.idea/libraries/Dart_SDK.xml'
        library = ET.parse(path).find("./library[@name='Dart SDK']")
        roots = library.findall('./CLASSES/root')
        self.assertTrue(roots)
        directories = {Path(unquote(item.get('url').removeprefix('file://')))
                       for item in roots}
        dart_lib = self.sdk.resolve() / 'bin/cache/dart-sdk/lib'
        self.assertIn(dart_lib / 'core', directories)
        self.assertIn(dart_lib / 'async', directories)
        self.assertTrue(all(directory.is_dir() for directory in directories))

    def test_repeated_repair_is_noop_and_keeps_original_backup(self):
        idea = self.project / '.idea'
        original = '''<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager"><content url="file://$MODULE_DIR$" /></component>
</module>
'''
        self.write(idea / 'AnyDeck.iml', original)
        self.assertTrue(config.configure(self.project, self.sdk))
        backup = idea / '.anydeck-backup/AnyDeck.iml'
        self.assertEqual(backup.read_text(), original)
        snapshot = self.snapshot(idea)
        self.assertEqual(config.configure(self.project, self.sdk), [])
        self.assertEqual(self.snapshot(idea), snapshot)
        self.write(idea / 'AnyDeck.iml', original.replace('version="4"', 'version="4" custom="1"'))
        config.configure(self.project, self.sdk)
        self.assertEqual(backup.read_text(), original)

    def test_missing_project_or_sdk_input_never_writes_configuration(self):
        required = [
            self.project / 'pubspec.yaml',
            self.project / 'lib/main.dart',
            self.sdk / 'bin/flutter',
            self.sdk / 'bin/cache/dart-sdk/bin/dart',
            self.sdk / 'bin/cache/dart-sdk/lib/core',
        ]
        for path in required:
            with self.subTest(path=path):
                hidden = path.with_name(path.name + '.hidden')
                path.rename(hidden)
                before = self.snapshot(self.root)
                try:
                    with self.assertRaises(ValueError):
                        config.configure(self.project, self.sdk)
                    self.assertEqual(self.snapshot(self.root), before)
                    self.assertFalse((self.project / '.idea').exists())
                finally:
                    hidden.rename(path)

    def test_malformed_existing_xml_is_rejected_without_partial_writes(self):
        idea = self.project / '.idea'
        self.write(idea / 'misc.xml', '<project><component name="Keep" /></project>\n')
        for relative in ('AnyDeck.iml', 'modules.xml'):
            with self.subTest(relative=relative):
                path = idea / relative
                self.write(path, '<project><broken>')
                before = self.snapshot(self.root)
                try:
                    with self.assertRaises((ET.ParseError, ValueError)):
                        config.configure(self.project, self.sdk)
                    self.assertEqual(self.snapshot(self.root), before)
                    self.assertFalse((idea / '.anydeck-backup').exists())
                finally:
                    path.unlink()

    def test_unknown_or_malformed_configuration_never_partially_writes(self):
        idea = self.project / '.idea'
        self.write(idea / 'misc.xml', '<project><component name="Keep" /></project>\n')
        cases = (
            ('modules.xml', '<project><component name="Unknown"><modules /></component></project>'),
            ('runConfigurations/AnyDeck.xml', '<component><broken>'),
            ('runConfigurations/AnyDeck.xml', '<component name="Unknown"><configuration name="AnyDeck" /></component>'),
            ('runConfigurations/AnyDeck_No_Share_Core.xml', '<component><broken>'),
            ('runConfigurations/AnyDeck_No_Share_Core.xml', '<component name="Unknown"><configuration name="AnyDeck" /></component>'),
            ('libraries/Dart_SDK.xml', '<component><broken>'),
            ('libraries/Dart_SDK.xml', '<component name="libraryTable"><library name="Unknown SDK" /></component>'),
        )
        for relative, contents in cases:
            with self.subTest(relative=relative, contents=contents):
                path = idea / relative
                self.write(path, contents)
                before = self.snapshot(self.root)
                try:
                    with self.assertRaises((ET.ParseError, ValueError)):
                        config.configure(self.project, self.sdk)
                    self.assertEqual(self.snapshot(self.root), before)
                    self.assertFalse((idea / '.anydeck-backup').exists())
                finally:
                    path.unlink()


if __name__ == '__main__':
    unittest.main()
