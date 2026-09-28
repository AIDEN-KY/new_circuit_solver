from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager


class RateLimitExceeded(ValueError):
    pass


class AccountBusyError(ValueError):
    pass


class SlidingWindowLimiter:
    """单机内测使用的内存滑动窗口限流器。"""

    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def check(self, key: str, *, limit: int, window_seconds: int) -> None:
        now = time.monotonic()
        async with self._lock:
            events = self._events[key]
            cutoff = now - window_seconds
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= limit:
                raise RateLimitExceeded("请求过于频繁，请稍后再试")
            events.append(now)


class SolveConcurrencyGuard:
    def __init__(self, max_global: int) -> None:
        self._global = asyncio.Semaphore(max_global)
        self._active_accounts: set[str] = set()
        self._lock = asyncio.Lock()

    @asynccontextmanager
    async def acquire(self, account_id: str):
        acquired = False
        async with self._lock:
            if account_id in self._active_accounts:
                raise AccountBusyError("该账号已有题目正在识别，请等待完成")
            self._active_accounts.add(account_id)
        try:
            await self._global.acquire()
            acquired = True
            yield
        finally:
            if acquired:
                self._global.release()
            async with self._lock:
                self._active_accounts.discard(account_id)
