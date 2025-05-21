from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from Web.db import create_user, validate_user

app = FastAPI()
templates = Jinja2Templates(directory="Web/templates")
app.mount("/static", StaticFiles(directory="Web/static"), name="static")


@app.get("/", response_class=HTMLResponse)
def main_page(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/signup", response_class=HTMLResponse)
def signup_get(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request})


@app.post("/signup")
def signup_post(
    request: Request,
    username: str = Form(...),
    email: str = Form(...),
    password: str = Form(...)
):
    create_user(username, email, password)
    return RedirectResponse("/", status_code=302)


@app.get("/login", response_class=HTMLResponse)
def login_get(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})


@app.post("/login")
def login_post(
    email: str = Form(...),
    password: str = Form(...)
):
    if validate_user(email, password):
        return RedirectResponse("/", status_code=302)
    return {"error": "로그인 실패"}
