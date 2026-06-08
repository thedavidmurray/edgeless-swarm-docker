"""
Paperclip API Stub — Minimal task tracker for Swarm-in-a-Box
===========================================================
This is a lightweight stand-in for the real Paperclip API. It provides:
  - Health checks
  - CRUD for issues (EDGA- prefixed IDs)
  - In-memory storage (lost on restart unless mounted volume is used)

In production, swap this out for the real Paperclip service or an external
Paperclip instance at http://host:3100.
"""

import json
import os
import uuid
from pathlib import Path
from datetime import datetime
from typing import List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Paperclip API (Stub)", version="0.1.0")

DATA_DIR = Path(os.environ.get("PAPERCLIP_DATA_DIR", "/data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_FILE = DATA_DIR / "issues.jsonl"

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class Issue(BaseModel):
    id: str = Field(default_factory=lambda: f"EDGA-{uuid.uuid4().hex[:8].upper()}")
    title: str
    description: str = ""
    status: str = "open"          # open | in_progress | closed | archived
    priority: str = "medium"      # low | medium | high | critical
    assignee: Optional[str] = None
    labels: List[str] = []
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

class IssueCreate(BaseModel):
    title: str
    description: str = ""
    status: str = "open"
    priority: str = "medium"
    assignee: Optional[str] = None
    labels: List[str] = []

class IssueUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    assignee: Optional[str] = None
    labels: Optional[List[str]] = None

# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------
def _load_all() -> List[Issue]:
    issues = []
    if DB_FILE.exists():
        with open(DB_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    issues.append(Issue(**json.loads(line)))
                except Exception:
                    pass
    return issues


def _save_all(issues: List[Issue]) -> None:
    with open(DB_FILE, "w", encoding="utf-8") as f:
        for issue in issues:
            f.write(json.dumps(issue.model_dump(), ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/api/health")
def health():
    return {"status": "ok", "service": "paperclip-stub", "issues_count": len(_load_all())}


@app.get("/api/issues")
def list_issues(status: Optional[str] = None, assignee: Optional[str] = None, limit: int = 100):
    issues = _load_all()
    if status:
        issues = [i for i in issues if i.status == status]
    if assignee:
        issues = [i for i in issues if i.assignee == assignee]
    return issues[:limit]


@app.post("/api/issues", status_code=201)
def create_issue(body: IssueCreate):
    issue = Issue(**body.model_dump())
    issues = _load_all()
    issues.append(issue)
    _save_all(issues)
    return issue


@app.get("/api/issues/{issue_id}")
def get_issue(issue_id: str):
    for issue in _load_all():
        if issue.id == issue_id:
            return issue
    raise HTTPException(status_code=404, detail="Issue not found")


@app.put("/api/issues/{issue_id}")
def update_issue(issue_id: str, body: IssueUpdate):
    issues = _load_all()
    for idx, issue in enumerate(issues):
        if issue.id == issue_id:
            data = issue.model_dump()
            update = body.model_dump(exclude_unset=True)
            update["updated_at"] = datetime.utcnow().isoformat()
            data.update(update)
            issues[idx] = Issue(**data)
            _save_all(issues)
            return issues[idx]
    raise HTTPException(status_code=404, detail="Issue not found")


@app.delete("/api/issues/{issue_id}")
def delete_issue(issue_id: str):
    issues = _load_all()
    for idx, issue in enumerate(issues):
        if issue.id == issue_id:
            issues.pop(idx)
            _save_all(issues)
            return {"deleted": True}
    raise HTTPException(status_code=404, detail="Issue not found")


# ---------------------------------------------------------------------------
# Seed data (optional)
# ---------------------------------------------------------------------------
@app.on_event("startup")
def seed():
    if not DB_FILE.exists() or DB_FILE.stat().st_size == 0:
        sample = Issue(
            title="Swarm-in-a-Box Setup",
            description="Initial setup complete. Replace this stub with real Paperclip when ready.",
            status="closed",
            priority="high",
            labels=["setup", "docker"]
        )
        _save_all([sample])
