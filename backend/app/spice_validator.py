from __future__ import annotations

import re

from .models import SpiceNetlist


_ELEMENT_RE = re.compile(r"^[RCLVIDQMETGHFSXJ][A-Za-z0-9_.$:-]*$", re.IGNORECASE)


def validate_spice_netlist(netlist: SpiceNetlist) -> SpiceNetlist:
    """执行不依赖外部仿真器的安全语法校验，不运行网表中的任何命令。"""
    messages: list[str] = []
    elements: list[str] = []
    names: set[str] = set()
    lines = [line.strip() for line in netlist.raw.splitlines() if line.strip()]
    if not lines:
        messages.append("网表为空")
    has_end = False
    for number, line in enumerate(lines, start=1):
        if line.startswith("*"):
            continue
        tokens = line.split()
        head = tokens[0].lower()
        if head == ".end":
            has_end = True
            continue
        if head.startswith("."):
            if head not in {".title", ".op", ".tran", ".ac", ".dc", ".options"}:
                messages.append(f"第{number}行包含不支持的控制语句：{tokens[0]}")
            continue
        if not _ELEMENT_RE.match(tokens[0]):
            messages.append(f"第{number}行元件名无效：{tokens[0]}")
            continue
        if tokens[0].lower() in names:
            messages.append(f"元件名重复：{tokens[0]}")
        names.add(tokens[0].lower())
        if len(tokens) < 4:
            messages.append(f"第{number}行缺少节点或参数：{line}")
        else:
            elements.append(line)
    if not has_end:
        messages.append("网表缺少 .end")
    node_names: set[str] = set()
    for line in elements:
        node_names.update(line.split()[1:3])
    if len(node_names) < 2:
        messages.append("有效节点少于两个，无法形成电路")
    return netlist.model_copy(
        update={
            "elements": elements,
            "validation_passed": not messages,
            "validation_messages": messages,
        }
    )
