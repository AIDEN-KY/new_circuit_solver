# 小范围内测人工增加次数方案

本方案不是自动支付系统。App 不展示收款二维码、不判断付款结果，也不直接修改次数；管理员在线下核对后，
通过受控的后端工具增加次数。仅建议用于人数可控、管理员能够逐笔处理的封闭内测。

## App 弹窗文案

标题：获取更多搜题次数

正文：

> 本测试版暂不提供 App 内付款。如需增加搜题次数，请加入内测 QQ 群：{QQ群号}，并私聊群内指定管理员。
> 转账前请确认管理员身份，转账时必须附上你的软件用户 ID。管理员核对后会人工增加次数；处理完成后，
> 请返回“我的账号”页面点击“刷新剩余次数”。请勿向非指定管理员付款。

按钮：

- 复制用户 ID
- 我知道了

QQ群号未配置时不得展示虚假号码，弹窗应改为“请向测试负责人索取内测群联系方式”。

## QQ群公告文案

> 【Circuit Solver 内测次数申请说明】
>
> 1. 本群仅服务受邀内测用户，不提供 App 内扫码或自动充值。
> 2. 如需增加次数，请先在 App“我的账号”页面复制用户 ID，再私聊群内标注的指定管理员。
> 3. 付款前请向管理员确认次数、金额、处理时间和退款规则；转账备注必须填写软件用户 ID。
> 4. 请勿在群聊公开发送转账截图、手机号、真实姓名等个人信息。
> 5. 管理员核对后会人工发放次数。收到通知后，在 App 中点击“刷新剩余次数”。
> 6. 未到账、错充或退款问题请保留转账凭证并联系原管理员处理。谨防冒充管理员的私聊账号。

## 数据库设计

现有 `users.free_uses_remaining` 作为当前可用次数，所有修改必须发生在服务端事务中。

`manual_grants`：

| 字段 | 作用 |
| --- | --- |
| `id` | 内部唯一编号 |
| `user_id` | 软件用户 ID，外键关联 `users.id` |
| `uses` | 本次增加次数，只允许正整数 |
| `operator` | 实际操作管理员标识 |
| `reference_id` | 唯一业务流水号，防止重复到账 |
| `note` | 非敏感备注，不保存完整转账截图或金融账户信息 |
| `created_at` | 操作时间 |

`account_ledger` 同时写入 `adjustment` 记录，供用户端额度明细与后台审计使用。

## 管理后台伪代码

```text
require admin_session with permission "grant_uses"
validate csrf_token
validate user_id exists
validate uses is positive integer and within single-operation limit
validate reference_id is present and globally unique
show username + current remaining uses for second confirmation

begin database transaction
  insert manual_grants(user_id, uses, operator, reference_id, note)
  if duplicate reference_id: rollback and reject
  update users
    set free_uses_remaining = free_uses_remaining + uses
    where id = user_id
  insert account_ledger(event_type="adjustment", free_uses_delta=uses,
                        reference_id=reference_id)
commit

write security audit log with operator, target user, uses, IP and result
return new remaining uses
```

当前内测阶段优先使用后端命令行工具，不开放公网管理员页面，以减少管理员接口被攻击的风险：

```powershell
python -m app.grant_uses `
  --user-id "用户ID" `
  --uses 10 `
  --operator "管理员编号" `
  --reference "唯一业务流水号" `
  --note "内测人工发放"
```

## 风险与注意事项

1. 个人转账与软件订单没有自动关联，管理员必须逐笔核对，容易出现错充、漏充和延迟。
2. 必须使用唯一业务流水号并保留审计记录，重复提交同一笔凭证不得二次到账。
3. 用户 ID 输入错误可能给其他账号加次数；操作前必须同时核对用户名和当前次数。
4. QQ 内可能出现冒充管理员、钓鱼链接和伪造转账截图，应固定管理员名单并反复提示用户。
5. 不应在群聊公开用户 ID 与转账材料；转账截图可能包含姓名、金融账户等敏感信息。
6. 应明确次数价格、有效期、到账时限、退款条件、服务故障补偿和联系方式，避免误导或争议。
7. 人工发放只能增加正数；扣减、撤销和退款应走单独的双人复核流程，不应直接修改数据库。
8. 管理员工具只能在服务器内网或本机运行，不能把管理员密钥、数据库文件或管理接口放入 App。
9. 必须备份数据库，并定期核对 `manual_grants`、`account_ledger` 与实际转账记录。
10. 账号共享、批量注册领取赠送次数和自动化调用仍可能增加 AI 成本，需要注册限速与服务端限流。
11. 小范围内测扩大后，人工处理会迅速成为瓶颈，也会增加售后与对账成本。
12. 面向公众经营时可能涉及市场主体登记、税务、明码标价、凭证和消费者权益义务，应另行咨询专业人士。
13. 应按最小必要原则处理用户信息，设置保存期限和访问权限，不把 QQ 信息、支付材料用于其他目的。
14. 应核对 QQ、微信及应用分发平台的最新规则；本方案不能替代平台许可或合规支付渠道。

