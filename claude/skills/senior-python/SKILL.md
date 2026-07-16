---
name: senior-python
description: Deep Python patterns for project structure, async, typing, FastAPI, SQLAlchemy,
  and packaging
---

# Python

## Project Structure (src layout)
```
project/
  src/
    package/
      __init__.py
      main.py
      models.py
      services/
      repositories/
  tests/
    conftest.py
    test_main.py
  pyproject.toml
  README.md
```

## pyproject.toml Configuration

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "package"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.110",
    "sqlalchemy>=2.0",
    "pydantic>=2.0",
    "httpx",
]

[project.optional-dependencies]
dev = ["pytest>=8", "pytest-asyncio", "ruff", "mypy"]
```

## Async Patterns

### asyncio
```python
import asyncio
from asyncio import TaskGroup

async def fetch_all(urls: list[str]) -> list:
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch(url)) for url in urls]
    return [t.result() for t in tasks]
```

### anyio / Trio
```python
import anyio

async def worker(scope: anyio.CancelScope):
    async with anyio.open_file("data.txt") as f:
        content = await f.read()

async def main():
    async with anyio.create_task_group() as tg:
        tg.start_soon(worker, tg.cancel_scope)
```

## Type System

### Protocol
```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Drawable(Protocol):
    def draw(self) -> None: ...
```

### TypedDict
```python
from typing import TypedDict

class UserDict(TypedDict, total=False):
    id: int
    name: str
    email: str
```

### Pydantic v2
```python
from pydantic import BaseModel, Field, EmailStr

class User(BaseModel):
    id: int
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    tags: list[str] = []
```

## FastAPI Patterns
```python
from fastapi import FastAPI, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

app = FastAPI(title="API", version="1.0.0")

@app.get("/users/{uid}")
async def get_user(uid: int, db: AsyncSession = Depends(get_db)):
    user = await user_repo.get(db, uid)
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return user
```

## SQLAlchemy 2.0
```python
from sqlalchemy import create_engine, select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str]

async def get_users():
    async with AsyncSession(engine) as session:
        stmt = select(User).where(User.name.ilike("a%"))
        result = await session.execute(stmt)
        return result.scalars().all()
```

## Testing
```python
import pytest
from httpx import AsyncClient, ASGITransport

@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

@pytest.mark.asyncio
async def test_get_user(client: AsyncClient):
    resp = await client.get("/users/1")
    assert resp.status_code == 200
```

## Packaging
- **Hatch**: `hatch new`, `hatch build`, `hatch publish`
- **Flit**: `flit init`, `flit build`, `flit publish`
- **Setuptools**: classic but deprecated for new projects
- Prefer `hatch` or `flit` for modern PEP 517/518 builds.
