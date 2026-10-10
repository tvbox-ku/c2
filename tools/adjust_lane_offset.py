#!/usr/bin/env python3
"""
余裕空间主动避让 - 交互调参工具
在 C2 设备上通过 SSH 运行: python /data/openpilot/tools/adjust_lane_offset.py
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from openpilot.common.params import Params


def fmt_offset(val):
  return "OFF" if val == 0 else f"{val} cm"


def main():
  params = Params()

  try:
    offset = int(params.get("AdjustLaneOffset", encoding="utf8") or "0")
  except (TypeError, ValueError):
    offset = 0

  priority_mode = params.get_bool("dp_lat_lane_priority_mode")

  try:
    speed_based = int(params.get("dp_lat_lane_priority_mode_speed_based", encoding="utf8") or "0")
  except (TypeError, ValueError):
    speed_based = 0

  print("=" * 55)
  print("    余裕空间主动避让 (AdjustLaneOffset) 调参工具")
  print("=" * 55)
  print()
  print(f"  [1] 车道线优先模式:     {'ON  ✓' if priority_mode else 'OFF ✗'}  (必须开启)")
  print(f"  [2] 优先模式速度门槛:   {speed_based} km/h  (0=始终生效)")
  print(f"  [3] 余裕偏移量:         {fmt_offset(offset)}")
  print(f"      范围: 0~40 cm (5cm 步进, 内部上限 0.4m)")
  print()
  print("  ── 操作 ──")
  print("    + / -  : 偏移量 ±5cm")
  print("    0      : 关闭偏移 (OFF)")
  print("    m      : 切换车道线优先模式")
  print("    q      : 退出")
  print()

  if not priority_mode:
    print("  ⚠ 车道线优先模式未开启，余裕避让不会生效!")
    print()

  while True:
    try:
      cmd = input("  > ").strip().lower()
    except (EOFError, KeyboardInterrupt):
      break

    if cmd == 'q':
      break
    elif cmd == '+':
      offset = min(40, offset + 5)
      params.put("AdjustLaneOffset", str(offset))
      print(f"  → 余裕偏移量: {fmt_offset(offset)}")
    elif cmd == '-':
      offset = max(0, offset - 5)
      params.put("AdjustLaneOffset", str(offset))
      print(f"  → 余裕偏移量: {fmt_offset(offset)}")
    elif cmd == '0':
      offset = 0
      params.put("AdjustLaneOffset", "0")
      print(f"  → 余裕偏移量: OFF")
    elif cmd == 'm':
      priority_mode = not priority_mode
      params.put_bool("dp_lat_lane_priority_mode", priority_mode)
      print(f"  → 车道线优先模式: {'ON  ✓' if priority_mode else 'OFF ✗'}")
      if not priority_mode:
        print("  ⚠ 余裕避让需要车道线优先模式开启才能生效!")
    elif cmd == '':
      continue
    else:
      print("  未知命令。 + / - / 0 / m / q")
    print()

  print("退出。当前设置: 偏移=%s, 优先模式=%s" % (
    fmt_offset(offset), 'ON' if priority_mode else 'OFF'))


if __name__ == "__main__":
  main()
