from dataclasses import replace

from .config import Settings
from .main import create_app


# 公网进程强制关闭管理路由，并只信任 Cloudflare 注入的真实来源地址。
app = create_app(
    replace(
        Settings.from_env(),
        admin_routes_enabled=False,
        trust_cloudflare_headers=True,
    )
)
