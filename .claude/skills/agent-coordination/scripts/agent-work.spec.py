#!/usr/bin/env python3
"""Behavior checks for the local reservation command."""

import concurrent.futures
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("agent-work.py")


class AgentWorkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / ".gitignore").write_text("/.agent-work/\n", encoding="utf-8")
        subprocess.run(["git", "add", ".gitignore"], cwd=self.repo, check=True)
        subprocess.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "base"],
            cwd=self.repo,
            check=True,
        )

    def command(self, *args, cwd=None):
        return subprocess.run(
            ["python3", str(SCRIPT), *args],
            cwd=cwd or self.repo,
            text=True,
            capture_output=True,
        )

    def claim(self, task, owner, *extra, cwd=None):
        return self.command(
            "claim", "campaign", task, "--owner", owner, "--mode", "write", "--area", "invoices", *extra,
            cwd=cwd,
        )

    def test_only_one_terminal_can_claim_a_task(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda number: self.claim("part-1", f"tab-{number}"), range(8)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assertIn("Task already reserved", " ".join(result.stderr for result in results if result.returncode))

    def test_second_writer_in_same_worktree_is_refused(self):
        self.assertEqual(self.claim("part-1", "tab-1").returncode, 0)
        second = self.command(
            "claim", "campaign", "part-2", "--owner", "tab-2", "--mode", "write", "--area", "quotes"
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("Workspace already has a writer", second.stderr)

    def test_independent_worktree_writer_can_claim_a_different_area(self):
        other = Path(self.temporary.name) / "other"
        subprocess.run(["git", "worktree", "add", "-qb", "other", str(other)], cwd=self.repo, check=True)
        self.assertEqual(self.claim("part-1", "tab-1").returncode, 0)
        independent = self.command(
            "claim", "campaign", "part-2", "--owner", "tab-2", "--mode", "write", "--area", "quotes",
            cwd=other,
        )
        self.assertEqual(independent.returncode, 0, independent.stderr)
        overlap = self.claim("part-3", "tab-3", cwd=other)
        self.assertNotEqual(overlap.returncode, 0)

    def test_unknown_changes_require_inspection(self):
        (self.repo / "someone-elses-work.txt").write_text("in progress", encoding="utf-8")
        result = self.claim("part-1", "tab-1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unclaimed changes", result.stderr)
        self.assertEqual(self.claim("part-1", "tab-1", "--adopt-existing").returncode, 0)

    def test_expansion_checks_other_worktrees_without_releasing_claim(self):
        other = Path(self.temporary.name) / "other"
        subprocess.run(["git", "worktree", "add", "-qb", "other", str(other)], cwd=self.repo, check=True)
        first = self.claim("part-1", "tab-1")
        self.assertEqual(first.returncode, 0)
        identifier = first.stdout.split()[1]
        second = self.command(
            "claim", "campaign", "part-2", "--owner", "tab-2", "--mode", "write", "--area", "quotes",
            cwd=other,
        )
        self.assertEqual(second.returncode, 0)
        denied = self.command("expand", identifier, "--area", "quotes")
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn("Area overlaps", denied.stderr)
        accepted = self.command("expand", identifier, "--area", "payments")
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertIn("part-1", self.command("list").stdout)


if __name__ == "__main__":
    unittest.main()
