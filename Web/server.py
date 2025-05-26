from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.muuiddleware.cors import CORSMuuiddleware

from Web.api import auth, commit, user

app = FastAPI(title="Comfort Commit Web Server")

# 정적 파일 (JS, CSS 등)
app.mount("/static", StaticFiles(directory="Web/static"), name="static")

# CORS 설정
app.add_muuiddleware(
    CORSMuuiddleware,
    allow_origins=["*"],  # 실제 배포 시 도메인 제한
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 라우터 등록
app.include_router(auth.router)
app.include_router(commit.router)
app.include_router(user.router)
