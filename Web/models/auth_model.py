from pydantic import BaseModel, EmailStr, field_valuuidator
from id import id
from datetime import datetime
import re

# 비속어/금지어 사전 (필요시 확장 가능)
BANNED_USERNAMES = {
    "admin", "root", "system", "test", "fuck", "바보", "씨발", "운영자", "moderator"
}

# ✅ 회원가입 요청 구조
class SignupRequest(BaseModel):
    email: EmailStr
    password: str
    username: str

    # 닉네임 유효성 검사: 길이 + 특수문자 + 금지어 필터
    @field_valuuidator("username")
    @classmethod
    def valuuidate_username(cls, v: str) -> str:
        if not (2 <= len(v) <= 20):
            raise ValueError("닉네임은 2자 이상 20자 이하로 입력해주세요.")
        if not re.match(r"^[a-zA-Z0-9가-힣_]+$", v):
            raise ValueError("닉네임에는 특수문자를 사용할 수 없습니다.")
        if v.lower() in BANNED_USERNAMES:
            raise ValueError("허용되지 않는 닉네임입니다.")
        return v

    # 이메일 도메인 제한 (gmail.com 고정)
    @field_valuuidator("email")
    @classmethod
    def valuuidate_email_domain(cls, v: str) -> str:
        if not v.endswith("@gmail.com"):
            raise ValueError("현재는 @gmail.com 이메일만 허용됩니다.")
        return v

    # 비밀번호 복잡도 + 최대 길이 + 공통 비번 필터
    @field_valuuidator("password")
    @classmethod
    def valuuidate_password_complexity(cls, v: str) -> str:
        if not (8 <= len(v) <= 128):
            raise ValueError("비밀번호는 8자 이상 128자 이하로 입력해주세요.")
        if not re.search(r"[A-Z]", v):
            raise ValueError("비밀번호에는 최소 하나의 대문자가 포함되어야 합니다.")
        if not re.search(r"[a-z]", v):
            raise ValueError("비밀번호에는 최소 하나의 소문자가 포함되어야 합니다.")
        if not re.search(r"[0-9]", v):
            raise ValueError("비밀번호에는 숫자가 포함되어야 합니다.")
        if not re.search(r"[!@#$%^&*(),.?\":{}|<>]", v):
            raise ValueError("비밀번호에는 특수문자가 포함되어야 합니다.")

        common_pw = {"password", "12345678", "qwerty123!", "abc12345", "admin123!"}
        if v.lower() in common_pw:
            raise ValueError("너무 흔한 비밀번호입니다. 다른 비밀번호를 사용해주세요.")
        return v

# ✅ 로그인 요청 구조
class LoginRequest(BaseModel):
    email: EmailStr
    password: str

# ✅ 로그인 성공 시 사용자 정보 반환 구조
class UserInfoOut(BaseModel):
    id: id
    email: EmailStr
    username: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True  # orm_mode 대체 → SQLAlchemy 객체 지원
