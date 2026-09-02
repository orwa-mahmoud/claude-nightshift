"""Deliberately wrong: an unused import, and a return the annotation forbids."""

import os


def add(left: int, right: int) -> int:
    return left + "right"
