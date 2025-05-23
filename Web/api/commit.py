from fastapi import APIRouter, Request, Depends, Form
from Web.db import get_db
from sqlalchemy.orm import Session
from models import CommitMessageInfo, CommitReviewLog, UserInfo
from fastapi.responses import HTMLResponse, RedirectResponse

router = APIRouter()

@router.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request, db: Session = Depends(get_db)):
    commits = db.query(CommitMessageInfo).filter(CommitMessageInfo.status == "pending").all()
    return templates.TemplateResponse("index.html", {"request": request, "commits": commits})

@router.get("/review/{commit_id}", response_class=HTMLResponse)
def review_page(commit_id: int, request: Request, db: Session = Depends(get_db)):
    commit = db.query(CommitMessageInfo).get(commit_id)
    return templates.TemplateResponse("review_commit.html", {"request": request, "commit": commit})

@router.post("/review/{commit_id}/submit")
def finalize_commit(commit_id: int, final_msg: str = Form(...), request: Request = None, db: Session = Depends(get_db)):
    commit = db.query(CommitMessageInfo).get(commit_id)
    commit.commit_msg = final_msg
    commit.status = "committed"
    commit.editable = False

    log = CommitReviewLog(
        commit_id=commit.id,
        final_msg=final_msg,
        approved=True,
        edited=True
    )

    db.add(log)
    db.commit()
    return RedirectResponse(url="/dashboard", status_code=302)
