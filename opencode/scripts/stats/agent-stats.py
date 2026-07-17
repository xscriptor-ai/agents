#!/usr/bin/env python3
"""agent-stats.py - Statistics about the agent collection.
Usage: ./stats/agent-stats.py [--agents PATH] [--format text|json]
"""
import argparse, collections, json, os, re, sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agents', default=None)
    parser.add_argument('--format', default='text', choices=['text', 'json'])
    args = parser.parse_args()

    agents_dir = Path(args.agents) if args.agents else Path(__file__).resolve().parent.parent.parent / 'agents'
    if not agents_dir.is_dir():
        print(f"Error: agents directory not found: {agents_dir}", file=sys.stderr)
        sys.exit(1)

    group_counts = collections.Counter()
    temp_buckets = collections.Counter()
    color_counts = collections.Counter()
    perm_counts = collections.Counter()
    total_lines = 0
    total_files = 0

    for f in sorted(agents_dir.rglob('*.md')):
        if f.name == 'README.md':
            continue
        total_files += 1
        text = f.read_text()
        total_lines += len(text.splitlines())

        group = f.parent.name
        parent = f.parent.parent.name
        if parent != agents_dir.name:
            group = f'{parent}/{group}'
        group_counts[group] += 1

        m = re.search(r'^temperature:\s*([\d.]+)', text, re.MULTILINE)
        if m:
            bucket = f'{float(m.group(1)):.1f}'
            temp_buckets[bucket] += 1

        m = re.search(r'^color:\s*[\"\']?([^\"\'\n]+)', text, re.MULTILINE)
        if m:
            color_counts[m.group(1).strip()] += 1

        for tool in ('edit', 'bash', 'glob', 'grep', 'read', 'list', 'webfetch'):
            m = re.search(rf'^{tool}:\s*(\S+)', text, re.MULTILINE)
            if m:
                perm_counts[f'{tool}={m.group(1)}'] += 1

    if args.format == 'json':
        data = {
            'total_agents': total_files,
            'avg_lines': total_lines // max(total_files, 1),
            'groups': [{'group': g, 'count': c} for g, c in group_counts.most_common()],
            'temperatures': dict(temp_buckets),
            'colors': dict(color_counts.most_common(10)),
        }
        json.dump(data, sys.stdout, indent=2)
        print()
    else:
        print('==> Agent Statistics\n')
        print(f'Total agents: {total_files}')
        print(f'Average lines per agent: {total_lines // max(total_files, 1)}\n')
        print('By group:')
        for g, c in group_counts.most_common():
            print(f'  {g:<30} {c:3d}')
        print('\nTemperature distribution:')
        for t in ['0.0','0.1','0.2','0.3','0.4','0.5']:
            print(f'  {t}: {temp_buckets[t]:3d} agents')
        print('\nMost used colors:')
        for c, n in color_counts.most_common(5):
            print(f'  {c:<20} {n:3d}')

if __name__ == '__main__':
    main()
