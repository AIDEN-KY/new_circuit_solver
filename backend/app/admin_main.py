from dataclasses import replace

from .config import Settings
from .main import create_app


# 管理进程只由启动脚本绑定到 127.0.0.1:8001。
app = create_app(
    replace(
        Settings.from_env(),
        admin_routes_enabled=True,
        trust_cloudflare_headers=False,
    )
)
