#!/usr/bin/env python3
"""Extract the full Apache raw log without unpacking archive paths."""
import pathlib
import shutil
import sys
import tarfile


def extract(source, target):
    with tarfile.open(source, 'r:gz') as archive:
        candidates = [m for m in archive.getmembers()
                      if m.isfile() and 0 < m.size < 100_000_000
                      and pathlib.PurePosixPath(m.name).name == 'Apache.log']
        if len(candidates) != 1:
            raise ValueError('Expected exactly one nonempty full Apache.log in archive')
        member = candidates[0]
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.extractfile(member) as src, target.open('wb') as dst:
            shutil.copyfileobj(src, dst)
        print(f'Extracted {member.name} ({member.size} bytes)')


if __name__ == '__main__':
    extract(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
