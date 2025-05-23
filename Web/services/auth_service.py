# 📁 webs/services/auth_service.py

from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from uuid import uuid4
from datetime import datetime, timedelta
import bcrypt

from webs.models.auth_model import UserInfo, UserSecret, UserSession
from webs.models.activity_model import UserActionLog
from webs.schemas.auth_schema import SignupRequest, LoginRequest
from webs.exceptions.auth_exceptions import (
    DuplicateEmailError,
    DuplicateUsernameError,
    InvalidPasswordError,
    UserNotFoundError,
)
from webs.config import PASSWORD_HASH_ROUNDS  # 👈 config에서 라운드 수 관리

# ✅ 회원가입 처리
def create_user(data: SignupRequest, db: Session, user_agent: str = "", ip_address: str = "") -> UserInfo:
    user_uuid = uuid4()
    now = datetime.utcnow()

    # bcrypt 해시 생성 (config 기준 rounds 사용)
    hashed_pw = bcrypt.hashpw(data.password.encode("utf-8"), bcrypt.gensalt(PASSWORD_HASH_ROUNDS)).decode("utf-8")

    user = UserInfo(
        uuid=user_uuid,
        email=data.email,
        username=data.username,
        is_active=True,
        created_at=now,
        updated_at=now
    )

    secret = UserSecret(
        uuid=user_uuid,
        password_hash=hashed_pw
    )

    try:
        db.add(user)
        db.add(secret)
        db.commit()
        db.refresh(user)
    except IntegrityError as e:
        db.rollback()
        # UNIQUE 제약 조건 이름 기반 분기
        if 'user_info_email_key' in str(e):
            raise DuplicateEmailError("이미 등록된 이메일입니다.")
        if 'user_info_username_key' in str(e):
            raise DuplicateUsernameError("이미 사용 중인 닉네임입니다.")
        raise e

    # 🔍 회원가입 로그 기록
    action_log = UserActionLog(
        uuid=user_uuid,
        action="signup_success",
        context="web",
        metadata={"ip": ip_address, "user_agent": user_agent},
        created_at=now
    )
    db.add(action_log)
    db.commit()

    return user

# ✅ 로그인 및 세션 생성
def authenticate_user(data: LoginRequest, db: Session, user_agent: str = "", ip_address: str = "") -> str:
    now = datetime.utcnow()

    user = db.query(UserInfo).filter(UserInfo.email == data.email).first()
    if not user:
        raise UserNotFoundError("존재하지 않는 이메일입니다.")

    secret = db.query(UserSecret).filter(UserSecret.uuid == user.uuid).first()
    if not secret or not bcrypt.checkpw(data.password.encode(), secret.password_hash.encode()):
        raise InvalidPasswordError("비밀번호가 일치하지 않습니다.")

    # ✅ 이전 세션 만료 처리 (optional)
    db.query(UserSession).filter(
        UserSession.user_id == user.id,
        UserSession.expires_at > now
    ).update({UserSession.expires_at: now})

    # 새로운 세션 발급
    access_token = uuid4().hex
    refresh_token = uuid4().hex

    session = UserSession(
        user_id=user.id,
        session_id=uuid4(),
        access_token=access_token,
        refresh_token=refresh_token,
        expires_at=now + timedelta(hours=1),
        last_seen=now,
        ip_address=ip_address,
        user_agent=user_agent
    )

    db.add(session)

    # 🔍 로그인 성공 로그
    log = UserActionLog(
        uuid=user.uuid,
        action="login_success",
        context="web",
        metadata={"ip": ip_address, "user_agent": user_agent},
        created_at=now
    )
    db.add(log)

    db.commit()
    return access_token
