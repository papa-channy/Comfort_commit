from fastapi import APIRouter, Form, Depends
from sqlalchemy.orm import Session
from Web.db import get_db
from models import UserPlan, UserPlanHistory
from uuid import uuid4
from datetime import datetime, timedelta

router = APIRouter()

@router.post("/upgrade_plan")
def upgrade_plan(uuid: str = Form(...), plan_key: str = Form(...), db: Session = Depends(get_db)):
    plan = db.query(UserPlan).filter(UserPlan.uuid == uuid).first()
    old_key = plan.plan_key
    plan.plan_key = plan_key
    plan.updated_at = datetime.utcnow()
    plan.expires_at = datetime.utcnow() + timedelta(days=30)

    hist = UserPlanHistory(
        uuid=uuid,
        old_plan_key=old_key,
        new_plan_key=plan_key,
        changed_by="user",
        changed_at=datetime.utcnow()
    )

    db.add(hist)
    db.commit()
    return {"result": "success"}
