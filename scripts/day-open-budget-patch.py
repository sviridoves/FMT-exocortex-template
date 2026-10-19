#!/usr/bin/env python3
"""Patch DayPlan budget line with deterministic sum from plan table.

Replaces whatever the LLM wrote with the actual sum of the h column.
Reads optional phys_hours override from priorities.yaml; defaults to h_rp
(multiplier = 1.0x) when not set.
"""

import re
import sys
import argparse
from pathlib import Path

try:
    import yaml as _yaml
    _YAML_AVAILABLE = True
except ImportError:
    _YAML_AVAILABLE = False


BUDGET_RE = re.compile(
    # BUGFIX (2026-07-11): матчить всю строку, не только уже-корректный шаблон — иначе
    # свободный текст от LLM-заполнения ("45-52h всего / ~7-8×") не находит совпадения,
    # и patch_budget() тихо пропускает замену (main(): "budget line not found — skipping").
    # RELABEL (2026-09-01, Ф148): matches BOTH the old "Бюджет дня" label (still what
    # cached/pre-fix LLM output and the day-open-scaffold.sh placeholder may contain
    # until every producer is migrated) and the new "Портфель в работе" label this
    # script now writes — the two-name window is exactly the kind of silent decoupling
    # this session exists to fix; a regex matching only the new label would make this
    # patch step itself invisibly stop finding the line the day the label diverges.
    r"\*\*(?:Бюджет дня|Портфель в работе):\*\*.*"
)

# BUGFIX (2026-09-01, Ф148/WP-484): реальные ячейки колонки "h" пишутся с суффиксом
# ("6h", "46h"), не голыми числами — прежний regex `^\d+(\.\d+)?$` не совпадал ни
# с одной такой ячейкой, sum_plan_hours() всегда возвращала 0.0, и патч молча
# "skipping"-ал КАЖДЫЙ день (day-open-pipeline.sh глушит любой exit кодом `|| true`,
# ни разу не заметно ни в логах, ни в самом DayPlan). Живой пример: DayPlan
# 2026-09-01 осталась с голым "103h" от LLM-заполнителя вместо декорированной
# детерминированной строки.
#
# BUGFIX (2026-10-19): ячейки пишутся и диапазонами ("1-2", "2-3", "2-3h") —
# прежний regex не совпадал ни с одной, сумма не считалась, строка LLM оставалась
# как есть и pre-commit блокировал DayPlan ("бюджет не в формате"). Для диапазона
# берём ВЕРХНЮЮ границу — консервативная планировочная цифра.
H_CELL_RE = re.compile(r"^(\d+(?:\.\d+)?)(?:-(\d+(?:\.\d+)?))?h?$")


def parse_h_cell(cell):
    """Hours from an h-column cell, or None if unrecognized. Range → upper bound."""
    m = H_CELL_RE.match(cell.strip())
    if not m:
        return None
    return float(m.group(2) if m.group(2) is not None else m.group(1))

ATTENTION_HEADER_RE = re.compile(r"(<summary><b>Требует внимания</b></summary>\s*\n)")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dayplan", required=True, help="Path to DayPlan .md")
    p.add_argument("--priorities", default=None, help="Path to priorities.yaml (optional)")
    return p.parse_args()


def detect_h_col(header_cells):
    """Return index of 'h' column in split table row, or None."""
    for i, cell in enumerate(header_cells):
        if cell.strip() == "h":
            return i
    return None


def sum_plan_hours(text):
    """Sum h column from the plan table (header row must contain 'h').

    Returns (total, table_found, rows_seen, rows_matched) — the three extra
    fields let the caller tell "no table today, nothing to sum" (legitimate,
    silent no-op) apart from "table has rows but none looked like an hour
    value" (format drift — the class of bug this script already missed once,
    see H_CELL_RE comment above)."""
    in_table = False
    h_col = None
    total = 0.0
    rows_seen = 0
    rows_matched = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            if in_table:
                break
            continue
        cells = stripped.split("|")
        # Separator row: all cells are dashes/colons
        if all(re.match(r"^[-:\s]*$", c) for c in cells):
            continue
        # Header detection
        if not in_table:
            h_col = detect_h_col(cells)
            if h_col is not None:
                in_table = True
            continue
        # Data row
        if h_col is not None and len(cells) > h_col:
            rows_seen += 1
            v = parse_h_cell(cells[h_col])
            if v is not None:
                rows_matched += 1
                total += v
    return total, in_table, rows_seen, rows_matched


def today_scoped_hours(text, today_wps):
    """Sum of the "h" column restricted to rows whose WP-ID is in today_wps —
    the pilot's own `today` list in priorities.yaml, not every WP that
    happens to be in_progress somewhere in the active portfolio table.

    Added same-day as the "Портфель в работе" relabel above, for the same
    reason: pilot caught that a 312h "Портфель в работе" figure answers a
    different question than "how many hours am I actually planning today"
    (14h for the 2 WPs he'd actually marked `today`) — showing only the
    portfolio-wide number left that question unanswered in the file itself.
    Returns None if today_wps is empty (nothing to scope to)."""
    if not today_wps:
        return None
    wp_res = [re.compile(rf"WP-{re.escape(str(wp).replace('WP-', '').strip())}(?!\d)") for wp in today_wps]
    in_table = False
    h_col = None
    total = 0.0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            if in_table:
                break
            continue
        cells = stripped.split("|")
        if all(re.match(r"^[-:\s]*$", c) for c in cells):
            continue
        if not in_table:
            h_col = detect_h_col(cells)
            if h_col is not None:
                in_table = True
            continue
        if h_col is not None and len(cells) > h_col and any(r.search(stripped) for r in wp_res):
            v = parse_h_cell(cells[h_col])
            if v is not None:
                total += v
    return total


def read_today_wps(priorities_path):
    """Return priorities.yaml's `today` list, or [] if unset/missing."""
    if not priorities_path:
        return []
    path = Path(priorities_path)
    if not path.exists() or not _YAML_AVAILABLE:
        return []
    with open(path, encoding="utf-8") as f:
        data = _yaml.safe_load(f) or {}
    return data.get("today") or []


def read_phys_hours(priorities_path):
    """Return phys_hours from priorities.yaml if explicitly set, else None."""
    if not priorities_path:
        return None
    path = Path(priorities_path)
    if not path.exists():
        return None
    if _YAML_AVAILABLE:
        with open(path, encoding="utf-8") as f:
            data = _yaml.safe_load(f) or {}
        val = data.get("phys_hours")
        return float(val) if val else None
    # PyYAML unavailable: fall back to single-line regex for this one key only
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^phys_hours:\s*([\d.]+)", line)
        if m:
            print("budget-patch: PyYAML not installed, using regex fallback for phys_hours", file=sys.stderr)
            return float(m.group(1))
    return None


def append_attention_finding(text, finding):
    """Same non-blocking-finding pattern as day-open-priorities-patch.py: write
    into the DayPlan's own «Требует внимания» section instead of failing the
    pipeline. Returns (patched_text, written: bool)."""
    line = f"- ⚠️ {finding}\n"
    patched, n = ATTENTION_HEADER_RE.subn(r"\1" + line, text, count=1)
    return (patched, True) if n else (text, False)


def patch_budget(text, h_rp, h_phys, today_h=None, partial=False):
    # RELABEL (2026-09-01, Ф148/WP-484, peer-session consensus with Codex):
    # h_rp is the sum of remaining-effort estimates across every in-flight WP
    # in the plan table — a portfolio-load figure, not a day's capacity (a
    # day physically caps out around 20-24h; this number reproducibly lands
    # in the hundreds once the H_CELL_RE fix above lets it sum correctly).
    # "Бюджет дня" claimed the latter; keep the number, fix the label. The
    # ~Xh РП / ~N.Nx substrings are unchanged on purpose — both are still
    # matched by protocol-artifact-validate.sh's format checks.
    mult = h_rp / h_phys if h_phys else 1.0
    replacement = (
        f"**Портфель в работе:** ~{h_rp:.0f}h РП"
        f" / ~{h_phys:.0f}h физ"
        f" / Плановый мультипликатор ~{mult:.1f}x"
    )
    if today_h is not None:
        # Separate day-scoped figure (same-day follow-up, pilot caught the
        # portfolio-wide number wasn't a day claim) — sourced from
        # priorities.yaml's `today` list, not this table's full row set.
        replacement += f" / РП на сегодня: ~{today_h:.0f}h"
    if partial:
        replacement += " / частичный расчёт"
    patched = BUDGET_RE.sub(replacement, text)
    if patched == text:
        # LLM мог переписать строку без метки **Бюджет дня:** / **Портфель в
        # работе:** (или без них совсем) — тогда BUDGET_RE не матчится.
        # Валидатор всё равно требует '~Xh РП' и '~N.Nx'; заменяем первую строку
        # с «мультипликатор» или с «всего», чтобы формат прошёл.
        fallback_re = re.compile(r"^.*(?:мультипликатор|всего|Бюджет|бюджет).*$", re.M)
        patched = fallback_re.sub(replacement, text, count=1)
    return patched


def main():
    args = parse_args()
    dayplan = Path(args.dayplan)
    text = dayplan.read_text(encoding="utf-8")

    h_rp, table_found, rows_seen, rows_matched = sum_plan_hours(text)

    if not table_found:
        print("budget-patch: no plan table today — skipping", file=sys.stderr)
        return

    partial = False
    unmatched = 0
    if rows_matched < rows_seen:
        # The table exists and has rows, but at least one didn't parse as an
        # hour value — the format-drift class of bug (H_CELL_RE comment
        # above). Cold review (2026-09-01) caught the original version of this
        # check only covering rows_matched == 0: a table where 2 of 3 rows
        # matched still silently computed an understated total from the
        # matched rows alone, with zero indication that one row was dropped.
        # 2026-10-19 (day-open rc=1 19.10): skipping the patch on partial
        # parse left the LLM's free-text budget line in place, which the
        # pre-commit validator then refused (format "не найден") — the pipeline
        # died after a green LLM fill. Now: write a format-valid line from the
        # matched rows anyway, mark it partial in the line itself and in
        # «Требует внимания». Never leave the free-text line for the
        # validator to choke on.
        partial = True
        unmatched = rows_seen - rows_matched

    if rows_matched == 0:
        # Nothing parsed: still replace the free-text line with a valid-format
        # honest zero, not "leave as LLM wrote". Format is required by
        # validate-staged-artifacts.sh; a 0 with the caveat is truthful.
        h_rp = 0.0
        h_phys = 0.0
        today_h = None
        partial = True
        unmatched = rows_seen
    else:
        h_phys = read_phys_hours(args.priorities) or h_rp
        today_wps = read_today_wps(args.priorities)
        today_h = today_scoped_hours(text, today_wps)

    patched = patch_budget(text, h_rp, h_phys, today_h, partial=partial)

    findings = []
    if partial:
        findings.append(
            f"«Портфель в работе»: {unmatched} из {rows_seen} строк(и) плана с "
            f"колонкой «h» не распознаны как число часов — сумма неполная"
        )

    for finding in findings:
        patched, written = append_attention_finding(patched, finding)
        if written:
            print(f"budget-patch: {finding}", file=sys.stderr)

    if patched == text:
        print(f"budget-patch: budget line not found or already correct (h_rp={h_rp})", file=sys.stderr)
        return

    dayplan.write_text(patched, encoding="utf-8")
    mult = (h_rp / h_phys) if h_phys else 1.0
    today_suffix = f" / сегодня ~{today_h:.0f}h" if today_h is not None else ""
    partial_suffix = " / частичный расчёт" if partial else ""
    print(f"budget-patch: ~{h_rp:.0f}h РП / ~{h_phys:.0f}h физ / ~{mult:.1f}x{today_suffix}{partial_suffix}", file=sys.stderr)


if __name__ == "__main__":
    main()
