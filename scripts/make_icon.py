"""生成 1024x1024 App 图标：深色渐变背景 + 均衡器条。"""
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024

def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

# 1) 全尺寸对角渐变背景
img = Image.new("RGB", (SIZE, SIZE))
px = img.load()
top = (58, 72, 138)      # 深靛蓝
bottom = (12, 14, 28)    # 近黑
for y in range(SIZE):
    t = y / (SIZE - 1)
    color = lerp_color(top, bottom, t)
    for x in range(SIZE):
        px[x, y] = color

# 2) 柔和径向光晕（中心偏上）
glow = Image.new("L", (SIZE, SIZE), 0)
gd = ImageDraw.Draw(glow)
cx, cy, radius = SIZE // 2, int(SIZE * 0.42), int(SIZE * 0.62)
for i in range(radius, 0, -8):
    alpha = int(34 * (1 - i / radius))
    gd.ellipse([cx - i, cy - i, cx + i, cy + i], fill=alpha)
glow = glow.filter(ImageFilter.GaussianBlur(60))
# 用 glow(L 灰度) 作为蒙版，把偏亮的颜色叠加到底图上，形成中心光晕
bright = Image.new("RGB", (SIZE, SIZE), (215, 222, 255))
img = Image.composite(bright, img, glow)

# 3) 均衡器条（白色圆角竖条）
overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
dr = ImageDraw.Draw(overlay)
bar_w = 84
gap = 64
heights = [330, 470, 380]
xs = [SIZE//2 - int((bar_w*3 + gap*2)/2) + i*(bar_w+gap) for i in range(3)]
base_y = int(SIZE * 0.62)
for x, h in zip(xs, heights):
    y0 = base_y - h
    dr.rounded_rectangle([x, y0, x + bar_w, base_y], radius=bar_w//2, fill=(255, 255, 255, 235))

# 4) 播放三角（右侧条前方）
tri_h = 210
tri_cx = xs[2] + bar_w + 52
tri_cy = base_y - 140
dr.polygon([(tri_cx, tri_cy - tri_h//2), (tri_cx, tri_cy + tri_h//2),
            (tri_cx + int(tri_h*0.86), tri_cy)], fill=(255, 255, 255, 255))

img = Image.alpha_composite(img.convert("RGBA"), overlay)

# 5) 轻微整体锐化与圆角裁切（iOS 会自动加圆角，这里留全幅矩形）
img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=120, threshold=2))

out = r"C:\Users\Administrator\Doubao\chats\2026-10-22\new-chat\LingYue\LingYue\Assets.xcassets\AppIcon.appiconset\AppIcon.png"
img.convert("RGB").save(out, "PNG")
print("saved", out, img.size)
