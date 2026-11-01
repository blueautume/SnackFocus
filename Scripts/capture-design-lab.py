#!/usr/bin/env python3
"""Capture the actual iOS renderers and layouts; requires a built Debug .app.

Example:
  python3 Scripts/capture-design-lab.py --device SIMULATOR_UDID --app-path /path/SnakeFocus.app
Pillow is needed only for assembling the two overview images.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
FORMS = [
    ('pixel', '像素生物'), ('ribbon', '流动丝带'), ('ink', '水墨游龙'),
    ('neon', '霓虹光管'), ('origami', '折纸鳞片'), ('clay', '软糖黏土'),
    ('chrome', '液态金属'), ('glass', '冰透玻璃'), ('pearl', '珍珠陶瓷'),
    ('hologram', '全息晶体'),
]
THEMES = [
    ('atelier', '轻盈工作室', 'clay'), ('zen', '侘寂庭院', 'ink'),
    ('arcade', '午夜街机', 'neon'), ('observatory', '轨道观测站', 'chrome'),
    ('gallery', '艺术画廊', 'origami'), ('dashboard', '专注仪表盘', 'glass'),
    ('paper', '纸上手记', 'ribbon'), ('candy', '糖果游乐场', 'pearl'),
    ('terminal', '极客终端', 'pixel'), ('aurora', '极光沉浸', 'hologram'),
]

def command(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)

def capture(device, destination, form, theme, board_only=False, delay=2.2):
    command('terminate', device, 'com.lihao.snakefocus', check=False)
    arguments = ['launch', device, 'com.lihao.snakefocus',
                 '-AppleLanguages', '(zh-Hans)', '-AppleLocale', 'zh_CN',
                 f'--lab-form={form}', f'--lab-theme={theme}']
    if board_only:
        arguments.append('--lab-board-only')
    command(*arguments)
    time.sleep(delay)
    command('io', device, 'screenshot', str(destination))
    print(f'Captured {destination.name}', flush=True)

def overviews(output, manifest):
    from PIL import Image, ImageDraw, ImageFont
    font_path = ROOT / 'SnakeFocus/Fonts/FusionPixel/fusion-pixel-12px-monospaced-zh_hans.otf'
    def font(size): return ImageFont.truetype(str(font_path), size)
    for kind, name, title in [('forms', 'snake-forms-overview.png', '10 种蛇形 / 实际 iOS 渲染'),
                              ('themes', 'interfaces-overview.png', '10 套界面 / 实际模拟器截图')]:
        canvas = Image.new('RGB', (2600, 2720), '#F6F4EF')
        draw = ImageDraw.Draw(canvas)
        draw.text((70, 40), f'SnakeFocus · {title}', font=font(54), fill='#252C28')
        subtitle = 'S01–S05 平面材质 · S06–S10 真实 3D · 同一试样与光照条件' if kind == 'forms' else 'T01–T10 独立布局 · 每套使用推荐蛇形 · 可在应用内自由组合'
        draw.text((72, 120), subtitle, font=font(27), fill='#677169')
        for index, item in enumerate(manifest[kind]):
            x = 70 + (index % 5) * 505
            y = 215 + (index // 5) * 1210
            with Image.open(output / item['file']) as source:
                image = source.convert('RGB')
                image.thumbnail((455, 1035), Image.Resampling.LANCZOS)
                canvas.paste(image, (x + (455-image.width)//2, y))
            draw.text((x, y+1055), f"{item['id']}  {item['title']}", font=font(33), fill='#252C28')
            detail = ('3D / ' if index >= 5 else '2D / ') + item['rawValue'] if kind == 'forms' else item['form']
            draw.text((x, y+1110), detail, font=font(23), fill='#677169')
        draw.text((72, 2650), '实验分支 · 可运行、可切换 · 图像均由应用截图生成', font=font(27), fill='#677169')
        canvas.save(output/name, optimize=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--app-path', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'Docs/Previews/DesignLab')
    parser.add_argument('--overviews-only', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    (output/'Snakes').mkdir(parents=True, exist_ok=True)
    (output/'Interfaces').mkdir(exist_ok=True)
    manifest = {'source': 'Actual simulator screenshots of native renderers, not generated concepts', 'forms': [], 'themes': []}
    for i, (form, title) in enumerate(FORMS, 1):
        manifest['forms'].append({'id': f'S{i:02d}', 'rawValue': form, 'title': title, 'file': f'Snakes/S{i:02d}-{form}.png'})
    for i, (theme, title, form) in enumerate(THEMES, 1):
        manifest['themes'].append({'id': f'T{i:02d}', 'rawValue': theme, 'title': title, 'form': form, 'file': f'Interfaces/T{i:02d}-{theme}.png'})
    if not args.overviews_only:
        if args.app_path:
            command('install', args.device, str(args.app_path.resolve()))
        command('status_bar', args.device, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
        for item in manifest['forms']:
            capture(args.device, output/item['file'], item['rawValue'], 'atelier', board_only=True, delay=3)
        for item in manifest['themes']:
            capture(args.device, output/item['file'], item['form'], item['rawValue'])
        command('terminate', args.device, 'com.lihao.snakefocus', check=False)
        command('launch', args.device, 'com.lihao.snakefocus', '-AppleLanguages', '(zh-Hans)', '-AppleLocale', 'zh_CN', '--lab-theme=atelier', '--lab-form=clay')
    (output/'catalog.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    overviews(output, manifest)
    print(f'Completed: {output}', flush=True)

if __name__ == '__main__':
    main()
