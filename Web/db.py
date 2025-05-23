from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "postgresql+psycopg2://user:password@localhost:5432/comfort_commit"  # 환경에 맞게 수정

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# FastAPI 종속형 Session Dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
