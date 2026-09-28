# Circuit Solver 1.7.0 后端

后端流程固定为“图片校验与裁剪 → AI Provider 识图 → AI 推理 → 结构化校验 → Flutter 协议响应”。生产代码不再读取题库；历史 `questions` 表暂不删除，三道教材题只用于内部 AI 回归。

## 本机安装

```powershell
cd backend
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
```

把 DeepSeek API Key 仅写入本机 `backend/.env`，不得写入 APK、GitHub、日志或动态配置。

## 1.7.0 公网内测

安装官方 `cloudflared` 后，在项目根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/start_public_beta.ps1
```

脚本会先备份 SQLite，再启动：

- 公共 API：`127.0.0.1:8000`，通过临时 `trycloudflare.com` HTTPS 地址访问，完全不注册 Admin 路由；
- 本机 Admin：`http://127.0.0.1:8001/admin`，不对局域网和公网监听；
- Cloudflare Quick Tunnel：只用于 1–10 人临时内测，地址重启后会变化。

停止全部进程：

```powershell
powershell -ExecutionPolicy Bypass -File tool/stop_public_beta.ps1
```

## 安全与额度

- 注册按来源地址每天最多5次；登录15分钟最多10次；超限返回429。
- 同一账号同时只能有1个搜题/追问；全局最多2次AI推理。
- 请求体最大10MB。
- App 为每次搜题发送 `client_request_id`；重复请求复用已完成结果，不重复扣次。
- 新用户赠送次数读取 `app_config`，只影响之后注册的账号。
- AI或图片处理失败会退款；次数和账号状态全部由服务端判断。
- 维护模式只阻止搜题和追问；健康、登录和账号信息仍可用。

## Admin 与动态配置

Admin 页面包括“用户管理”和“系统配置”。次数增减必须填写唯一流水号和备注，且不能减到0以下。所有配置变更、账号状态及次数调整写入审计表。

公开配置接口：`GET /api/v1/app-config`。管理接口仅存在于本机8001进程：

- `GET/PUT /api/v1/admin/config`
- `POST /api/v1/admin/users/{id}/adjust-uses`
- `POST /api/v1/admin/users/{id}/status`

## 备份与恢复检查

启动公网内测时自动备份并保留最近14份。单独检查备份：

```powershell
backend\.venv\Scripts\python.exe -m app.backup_database --verify backend\backups\备份文件.db
```

恢复脚本默认只校验；确认所有后端进程已停止后才添加 `-Apply`：

```powershell
powershell -ExecutionPolicy Bypass -File tool/restore_database.ps1 -BackupPath "完整备份路径"
powershell -ExecutionPolicy Bypass -File tool/restore_database.ps1 -BackupPath "完整备份路径" -Apply
```

## AI 回归

默认离线，不调用 API、不产生费用：

```powershell
cd backend
.venv\Scripts\python.exe -m app.evaluate
```

真实在线回归（会调用当前 Provider 并产生费用）：

```powershell
.venv\Scripts\python.exe -m app.evaluate --live
```

报告保存到 `backend/evals/reports/`，包含答案准确率、JSON结构成功率、单位正确率、置信度、耗时和逐题错误。Prompt 修改前后可直接比较报告。

## 测试

```powershell
cd backend
.venv\Scripts\python.exe -m pytest tests -q --basetemp ..\test-runtime -p no:cacheprovider
```
