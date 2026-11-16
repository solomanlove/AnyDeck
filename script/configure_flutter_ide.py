#!/usr/bin/env python3
"""修复 AnyDeck 的本机 Flutter IDE 配置，保留其他模块与用户设置。"""

import argparse
from copy import deepcopy
from pathlib import Path
import re
import shlex
import shutil
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr


CONTENT_ROOT = 'file://$MODULE_DIR$'
MODULE = '''<?xml version="1.0" encoding="UTF-8"?>
<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager" inherit-compiler-output="true">
    <exclude-output />
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
'''
MODULES = '''<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/.idea/AnyDeck.iml" filepath="$PROJECT_DIR$/.idea/AnyDeck.iml" />
    </modules>
  </component>
</project>
'''
RUN_CONFIG = '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="AnyDeck" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="additionalArgs" value="--no-pub" />
    <option name="filePath" value="$PROJECT_DIR$/lib/main.dart" />
    <method v="2" />
  </configuration>
</component>
'''
NO_SHARE_NAME = 'AnyDeck（不含 Share Core）'
SHARE_DEFINE = 'ANYDECK_ENABLE_SHARE_CORE'


def repair_module(text):
    """只修正主模块的路径和 Dart 依赖，不重新格式化已有 XML。"""
    # IntelliJ 对 .idea 内的 .iml 将 MODULE_DIR 定义为项目根目录。
    text = text.replace('file://$PROJECT_DIR$', CONTENT_ROOT)
    text = re.sub(r'file://\$MODULE_DIR\$/\.\.(?=/|["\'])', CONTENT_ROOT, text)
    root = ET.fromstring(text)
    manager = root.find("./component[@name='NewModuleRootManager']")
    if manager is None:
        raise ValueError('主模块缺少 NewModuleRootManager，未写入配置。')
    contents = manager.findall('content')
    if len(contents) != 1 or contents[0].get('url') != CONTENT_ROOT:
        raise ValueError('主模块根目录不明确，未写入配置。')
    content = contents[0]
    additions = []
    for name, is_test in (('lib', 'false'), ('test', 'true')):
        url = f'{CONTENT_ROOT}/{name}'
        if not any(node.get('url') == url for node in content.findall('sourceFolder')):
            additions.append(f'      <sourceFolder url="{url}" isTestSource="{is_test}" />')
    for name in ('.dart_tool', '.idea', 'build'):
        url = f'{CONTENT_ROOT}/{name}'
        if not any(node.get('url') == url for node in content.findall('excludeFolder')):
            additions.append(f'      <excludeFolder url="{url}" />')
    if additions:
        match = re.search(r'<content\b[^>]*\s*/>', text)
        if match:
            replacement = match.group().rsplit('/', 1)[0].rstrip() + '>\n'
            replacement += '\n'.join(additions) + '\n    </content>'
            text = text[:match.start()] + replacement + text[match.end():]
        else:
            text = text.replace('</content>', '\n'.join(additions) + '\n    </content>', 1)
    if not any(node.get('name') == 'Dart SDK' and node.get('level') == 'project'
               for node in manager.findall('orderEntry')):
        start = text.index('<component name="NewModuleRootManager"')
        end = text.index('</component>', start)
        text = (text[:end] + '    <orderEntry type="library" name="Dart SDK" level="project" />\n  '
                + text[end:])
    return text


def repair_run_config(text):
    """保留已有启动参数和环境变量，仅补齐入口与禁止自动解析依赖的参数。"""
    root = ET.fromstring(text, parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
    configs = root.findall('configuration')
    if (root.tag != 'component' or root.get('name') != 'ProjectRunConfigurationManager'
            or len(configs) != 1 or configs[0].get('type') != 'FlutterRunConfigurationType'):
        raise ValueError('AnyDeck.xml 不是唯一的 Flutter 运行配置，未写入配置。')
    config = configs[0]
    changed = False
    for name, value in (('filePath', '$PROJECT_DIR$/lib/main.dart'), ('additionalArgs', '--no-pub')):
        options = config.findall(f"option[@name='{name}']")
        if len(options) > 1:
            raise ValueError(f'运行配置存在重复 {name}，未写入配置。')
        option = options[0] if options else ET.SubElement(config, 'option', {'name': name})
        current = option.get('value', '')
        if name == 'additionalArgs':
            if '--no-pub' in shlex.split(current):
                continue
            value = (current + ' --no-pub').strip()
        if current != value:
            option.set('value', value)
            changed = True
    if not changed:
        return text
    ET.indent(root, space='  ')
    return ET.tostring(root, encoding='unicode') + '\n'


def no_share_arguments(current):
    """保留调试参数，同时移除冲突的构建模式和同名 Dart define。"""
    tokens = shlex.split(current)
    arguments = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        index += 1
        if token.split('=', 1)[0] in ('--release', '--profile', '--debug'):
            continue
        if token in ('--dart-define', '-D') and index < len(tokens):
            if tokens[index].startswith(f'{SHARE_DEFINE}='):
                index += 1
                continue
        if token.startswith((f'--dart-define={SHARE_DEFINE}=', f'-D{SHARE_DEFINE}=')):
            continue
        arguments.append(token)
    if '--no-pub' not in arguments:
        arguments.append('--no-pub')
    arguments.extend(('--debug', f'--dart-define={SHARE_DEFINE}=false'))
    return current if arguments == tokens else shlex.join(arguments)


def run_environment(configuration):
    """读取 Flutter 98 的 envs entry 格式，拒绝重复或不明确的环境变量。"""
    options = configuration.findall("option[@name='envs']")
    if len(options) > 1:
        raise ValueError('运行配置存在重复 envs，未写入配置。')
    if not options:
        return None, {}
    option = options[0]
    entries = {}
    for entry in option:
        if entry.tag is ET.Comment:
            continue
        if entry.tag != 'entry' or not entry.get('key') or entry.get('key') in entries:
            raise ValueError('运行配置 envs 格式不明确，未写入配置。')
        entries[entry.get('key')] = entry
    return option, entries


def repair_no_share_run_config(text, base_text):
    """生成独立 Debug 入口，继承工具链环境并隔离 Share Core 开关。"""
    repaired = repair_run_config(text if text is not None else base_text)
    parser = lambda: ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    root = ET.fromstring(repaired, parser=parser())
    configuration = root.find('configuration')
    base = ET.fromstring(base_text, parser=parser()).find('configuration')
    changed = False
    for key, value in (('name', NO_SHARE_NAME), ('default', 'false')):
        if configuration.get(key) != value:
            configuration.set(key, value)
            changed = True
    option = configuration.find("option[@name='additionalArgs']")
    current = option.get('value', '')
    arguments = no_share_arguments(current)
    if arguments != current:
        option.set('value', arguments)
        changed = True
    environment, entries = run_environment(configuration)
    _, inherited = run_environment(base)
    if environment is None:
        environment = ET.SubElement(configuration, 'option', {'name': 'envs'})
        changed = True
    for key, entry in inherited.items():
        if key not in entries:
            entries[key] = deepcopy(entry)
            environment.append(entries[key])
            changed = True
    skip = entries.get('ANYDECK_SKIP_SHARE_CORE')
    if skip is None:
        skip = ET.SubElement(environment, 'entry', {'key': 'ANYDECK_SKIP_SHARE_CORE'})
    if skip.get('value') != '1':
        skip.set('value', '1')
        changed = True
    if not changed:
        return repaired
    ET.indent(root, space='  ')
    return ET.tostring(root, encoding='unicode') + '\n'


def configure(project, sdk):
    """先验证全部输入，再备份并写入本机 .idea；重复执行不产生改动。"""
    project, sdk = Path(project).resolve(), Path(sdk).resolve()
    dart = sdk / 'bin/cache/dart-sdk'
    for file in (project / 'pubspec.yaml', project / 'lib/main.dart',
                 sdk / 'bin/flutter', dart / 'bin/dart'):
        if not file.is_file():
            raise ValueError(f'缺少必要文件：{file}')
    if not (dart / 'lib/core').is_dir():
        raise ValueError(f'Dart SDK 不完整：{dart}')
    idea = project / '.idea'
    module = idea / 'AnyDeck.iml'
    modules = idea / 'modules.xml'
    module_text = repair_module(module.read_text() if module.exists() else MODULE)
    modules_text = modules.read_text() if modules.exists() else MODULES
    modules_root = ET.fromstring(
        modules_text, parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
    module_tables = modules_root.findall(
        "./component[@name='ProjectModuleManager']/modules")
    if len(module_tables) != 1:
        raise ValueError('modules.xml 缺少唯一的 ProjectModuleManager，未写入配置。')
    registered = module_tables[0].findall('module')
    if not any(node.get('filepath') == '$PROJECT_DIR$/.idea/AnyDeck.iml'
               for node in registered):
        ET.SubElement(module_tables[0], 'module', {
            'fileurl': 'file://$PROJECT_DIR$/.idea/AnyDeck.iml',
            'filepath': '$PROJECT_DIR$/.idea/AnyDeck.iml',
        })
        ET.indent(modules_root, space='  ')
        modules_text = ET.tostring(modules_root, encoding='unicode') + '\n'
    roots = '\n'.join(
        f'      <root url={quoteattr("file://" + path.as_posix())} />'
        for path in sorted((dart / 'lib').iterdir()) if path.is_dir()
    )
    library = ('<component name="libraryTable">\n  <library name="Dart SDK">\n'
               f'    <CLASSES>\n{roots}\n    </CLASSES>\n'
               '    <JAVADOC />\n    <SOURCES />\n  </library>\n</component>\n')
    library_file = idea / 'libraries/Dart_SDK.xml'
    if library_file.exists():
        old_library = ET.parse(library_file).getroot()
        libraries = old_library.findall('library')
        if (old_library.tag != 'component' or old_library.get('name') != 'libraryTable'
                or len(libraries) != 1 or libraries[0].get('name') != 'Dart SDK'):
            raise ValueError('Dart_SDK.xml 不是唯一的 Dart SDK library，未写入配置。')
    run_file = idea / 'runConfigurations/AnyDeck.xml'
    run_text = repair_run_config(run_file.read_text() if run_file.exists() else RUN_CONFIG)
    no_share_file = idea / 'runConfigurations/AnyDeck_No_Share_Core.xml'
    no_share_text = repair_no_share_run_config(
        no_share_file.read_text() if no_share_file.exists() else None, run_text)
    planned = {
        module: module_text,
        modules: modules_text,
        library_file: library,
        run_file: run_text,
        no_share_file: no_share_text,
    }
    # 在首次写入前解析全部 XML，避免无效输入留下半套配置。
    for text in planned.values():
        ET.fromstring(text)
    changed = []
    for file, text in planned.items():
        if file.exists() and file.read_text() == text:
            continue
        backup = idea / '.anydeck-backup' / file.relative_to(idea)
        if file.exists() and not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, backup)
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)
        changed.append(file)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path, help='Flutter SDK 根目录')
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        changed = configure(args.project, args.sdk)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f'配置失败：{error}\n')
    for file in changed:
        print(f'已修复：{file}')
    print('配置已就绪，请重新打开项目并选择 macOS 运行目标。')


if __name__ == '__main__':
    main()
