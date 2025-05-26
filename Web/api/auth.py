from fastapi import APIRouter, Request, Form, Depends, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from Web.db import get_db
from sqlalchemy.orm import Session
from id import id4
import bcrypt
from models import UserInfo, UserSecret, UserSession

router = APIRouter()

@router.get("/signup", response_class=HTMLResponse)
def signup_page(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request})

@router.post("/signup")
def signup(email: str = Form(...), password: str = Form(...), username: str = Form(...), db: Session = Depends(get_db)):
    id = id4()
    if db.query(UserInfo).filter(UserInfo.email == email).first():
        raise HTTPException(400, "이미 존재하는 이메일입니다")

    hashed_pw = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    user = UserInfo(id=id, email=email, username=username)
    secret = UserSecret(id=id, password_hash=hashed_pw)

    db.add(user)
    db.add(secret)
    db.commit()

    return RedirectResponse(url="/login", status_code=302)

@router.get("/login", response_class=HTMLResponse)
def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@router.post("/login")
def login(email: str = Form(...), password: str = Form(...), request: Request = None, db: Session = Depends(get_db)):
    user = db.query(UserInfo).filter(UserInfo.email == email).first()
    if not user:
        raise HTTPException(401, "계정을 찾을 수 없습니다")

    secret = db.query(UserSecret).filter(UserSecret.id == user.id).first()
    if not bcrypt.checkpw(password.encode(), secret.password_hash.encode()):
        raise HTTPException(401, "비밀번호가 일치하지 않습니다")

    session = UserSession(
        user_uuid=user.uuid,
        session_uuid=id4(),
        access_token=id4().hex,
        refresh_token=id4().hex
    )
    db.add(session)
    db.commit()
    resp = RedirectResponse(url="/dashboard", status_code=302)
    resp.set_cookie("access_token", session.access_token)
    return resp
