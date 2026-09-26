# Circuit Solver 后端

后端严格保持 App 已约定的 `POST /api/v1/ask` 协议。处理顺序为：

1. 校验并解码 Data URI 图片。
2. 按 `crop_box` 裁剪题目区域。
3. 计算图片感知指纹，在 SQLite 题库中检索。
4. 达到相似度阈值时直接返回题库答案。
5. 未命中时先让 AI 只提取题干、元件、参数和连接关系。
6. 将结构化电路交给第二阶段进行纯文本推理，避免识图与计算互相干扰。
7. 服务端检查目标量覆盖、步骤与最终数值一致性、单位和置信度，再返回统一结构。

业务层不直接依赖 Ollama。`AI_PROVIDER=ollama` 使用本地模型；也可切换为
`AI_PROVIDER=deepseek` 或 `AI_PROVIDER=openai_compatible`，无需修改 Flutter App 或题库检索流程。云端模式还必须
配置 `AI_API_BASE_URL`、`AI_API_KEY` 和支持图片输入、JSON Schema 的 `AI_MODEL`。

## 安装和运行

需要 Python 3.11 或更高版本。

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

默认配置使用 `AI_PROVIDER=ollama` 和 `AI_MODEL=qwen3-vl:4b-instruct`。确认模型已安装后启动：

```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --env-file .env
```

示例将 Provider 超时设为 480 秒。本地模型首次加载通常明显慢于后续请求；应根据实际硬件测量调整，而不是移除超时。
`AI_MAX_OUTPUT_TOKENS` 默认限制为 1024，防止小模型在复杂题上过度展开并占满上下文。

DeepSeek两阶段模式会为识图阶段固定使用非思考模式和2048输出上限，为推理阶段使用低推理强度和
16384输出上限。Provider请求支持按阶段覆盖这两个参数；环境变量仍作为其他调用的默认值。

若旧款或小显存显卡在视觉编码阶段出现 `Vulkan device lost`，可按 Ollama 官方排障方式改用 CPU：

```powershell
$env:OLLAMA_LLM_LIBRARY="cpu_avx2"
$env:CUDA_VISIBLE_DEVICES="-1"
$env:GGML_VK_VISIBLE_DEVICES="-1"
ollama serve
```

测试版 App 的 Base URL 填写服务器根地址，例如真机访问局域网电脑时填写 `http://192.168.1.10:8000`，不要附加 `/api/v1/ask`。

## DeepSeek视觉模型

在本机 `backend/.env` 中配置以下内容（密钥不要提交到仓库）：

```dotenv
AI_PROVIDER=deepseek
AI_MODEL=deepseek-flash
AI_API_BASE_URL=https://api.deepseek.com
AI_API_KEY=在此填写自己的密钥
AI_TIMEOUT_SECONDS=180
AI_MAX_OUTPUT_TOKENS=8192
AI_REASONING_EFFORT=none
```

DeepSeek Provider 使用官方 Responses API 的图片输入和 JSON Schema 输出。没有密钥时只运行本地单元测试，
不会虚构云端调用成功。当前默认关闭思考模式：真实测试中 `high` 会把 8192 个输出 token
全部用于推理而没有生成最终答案；后续若提高输出上限并接受更高费用，可通过
`AI_REASONING_EFFORT=low|high|max` 重新评估。

## 导入题库

准备一张只包含题目区域的图片，以及一份符合 AskResponse 格式的 JSON：

```powershell
python -m app.import_question `
  --id q_1001 `
  --title "串联电路求电流" `
  --image data/q_1001.jpg `
  --response data/q_1001.json
```

只有最终答案、尚无可靠解题过程的样本应以待审核状态导入：

```powershell
python -m app.import_question `
  --id regression_001 `
  --title "教材回归题" `
  --image data/regression_001/question.jpg `
  --answer-image data/regression_001/answer.jpg `
  --response data/regression_001/response.json `
  --review-status pending_solution `
  --source-reference "教材答案页"
```

待审核题不会参与用户端检索，也不会作为相似题返回。补齐并人工审核完整步骤后，重新导入时增加
`--review-status approved --publishable` 才会正式发布。重复使用同一题目编号会更新已有记录。
SQLite 数据库默认保存在 `backend/data/circuit_solver.db`。

仓库自带的三道真实回归题可以一次性写入任意新数据库：

```powershell
python -m app.seed_regression
```

该命令只写入 `pending_solution + is_publishable=0` 记录，不会把只有最终答案的样本发布给用户。

## 测试

```powershell
python -m pip install -r requirements-dev.txt
pytest
```

本地视觉模型必须支持图片输入和结构化 JSON 输出。若模型未配置或服务不可用，接口会返回 HTTP 503，不会伪造答案。
