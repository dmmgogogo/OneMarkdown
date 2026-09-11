# 接口文档

## 第三方 API

通过 `Authorization: Bearer YOUR_API_KEY` 调用。游戏编号由平台分配，每个 Key 只能访问分配的游戏。

```curl
curl 'https://example.com/api/v1/games/22/draws/latest' \
  -H 'Authorization: Bearer YOUR_API_KEY'
```

| 方法 | 路径前缀 /api/v1 | 说明 |
|:-----|:-----------------|:-----|
| GET | /games | 授权游戏列表 |
| GET | /games/{game}/draws | 开奖列表 |
| GET | /games/{game}/draws/latest | 最新一期 |
| GET | /games/{game}/draws/{issue} | 指定期号 |
| GET | /games/{game}/export | 导出 CSV |

### 授权游戏列表

GET /games 的外层只有 data 数组，每个游戏只返回 id、name 两个字段。

| 字段 / 参数 | 类型 | 含义 |
|---|---|---|
| `id` | 整数 | 当前 Key 授权的游戏编号 |
| `name` | 字符串 | 游戏名称，供下游展示或选择 |

```json
{
  "data": [
    { "id": 22, "name": "示例游戏" },
    { "id": 23, "name": "另一个游戏" }
  ]
}
```

### 错误码

```bash
# 401 未授权
export TOKEN="bad"
curl -s -o /dev/null -w "%{http_code}\n" https://example.com/api/v1/games -H "Authorization: Bearer $TOKEN"
```

```python
import requests

resp = requests.get("https://example.com/api/v1/games", headers={"Authorization": f"Bearer {token}"})
print(resp.json()["data"])
```

```
无语言代码块：保持原样 <b>不会被解析成 HTML</b>
```

## 排版元素

### 列表

- 无序列表一
- 无序列表二
  - 嵌套项 A
  - 嵌套项 B
    1. 三层有序
    2. 三层有序

1. 有序一
2. 有序二

### 任务列表

- [x] 已完成的事项
- [ ] 未完成的事项
- [ ] 另一个未完成 `带代码`

### 引用与分隔线

> 这是一段引用。**加粗**、*斜体*、~~删除线~~、[链接](https://www.apple.com)。
>
> 第二段引用。

---

### 脚注

Markdown 的脚注语法[^1] 和另一个脚注[^note]。

[^1]: 这是第一个脚注的内容。
[^note]: 这是命名脚注，可以包含 `代码`。

### 图片

相对路径图片：

![演示图片](images/demo.png)

上级目录相对路径（等价于同一张图）：

![同一张图](../samples/images/demo.png)

不存在的图片：

![不存在](images/missing.png)

远程图片（联网时显示）：

![远程](https://www.apple.com/favicon.ico)

### 链接

- 外部链接：<https://developer.apple.com/>
- 相对 Markdown 链接：[子目录文档](sub/linked.md)
- 页内锚点：[跳到「授权游戏列表」](#授权游戏列表)
- 邮件：<hello@example.com>
- 自动识别的 URL：https://github.com

### 原始 HTML

<details>
<summary>点击展开</summary>

这里是 details 里的内容，**Markdown** 依然生效。

</details>

<script>alert('XSS')</script>

<p style="color: #d33">带 style 属性的段落（允许）</p>

<img src="x" onerror="alert('xss')">

### 重复标题

#### 重复

内容 A

#### 重复

内容 B（slug 应为 重复-1）

### 全角标点与 Emoji

「引号」、逗号，句号。感叹号！问号？——破折号 🎉 🚀 ✅

### 长表格

| 列一 | 列二 | 列三 | 列四 | 列五 | 列六 | 列七 | 列八 |
|---|---|---|---|---|---|---|---|
| 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 | 很长的内容很长的内容 |

## 结尾

最后一段。用于验证滚动到底部。

