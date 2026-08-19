import { createRoot } from 'react-dom/client'
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { ActionBarPrimitive, AssistantRuntimeProvider, ComposerPrimitive, MessagePrimitive, ThreadPrimitive, useLocalRuntime, type ChatModelAdapter } from '@assistant-ui/react'
import './style.css'

type Tab = 'chat' | 'embed' | 'ocr' | 'settings'
type Settings = { server: { host: string; port: number }; models: Record<string, string>; runtime: Record<string, number | boolean | string> }
type Health = { loaded_models?: Record<string, { model: string }>; effective_context_limit?: number }

const nav: Array<[Tab, string, string]> = [['chat', '◌', '对话'], ['embed', '⌘', '向量'], ['ocr', '▤', '文档 OCR'], ['settings', '⚙', '设置']]
const api = async <T,>(path: string, init: RequestInit = {}): Promise<T> => {
  const response = await fetch(`/ui/api/${path}`, { ...init, headers: { ...(init.body instanceof FormData ? {} : { 'Content-Type': 'application/json' }), ...init.headers } })
  if (!response.ok) throw new Error((await response.text()).replace(/^"|"$/g, '') || `请求失败 (${response.status})`)
  return response.json() as Promise<T>
}


function App() {
  const [tab, setTab] = useState<Tab>('chat')
  const [settings, setSettings] = useState<Settings | null>(null)
  const [health, setHealth] = useState<Health | null>(null)
  const [error, setError] = useState('')

  const refresh = async () => {
    try { const [s, h] = await Promise.all([api<Settings>('settings'), api<Health>('health')]); setSettings(s); setHealth(h); setError('') }
    catch (err) { setError(err instanceof Error ? err.message : '会话已失效') }
  }
  useEffect(() => { refresh(); const timer = setInterval(refresh, 15_000); return () => clearInterval(timer) }, [])

  if (error) return <div className="expired"><div><b>Kiln 会话已失效</b><p>{error}</p><code>kiln ui</code></div></div>
  if (!settings) return <div className="expired">正在连接 Kiln…</div>
  const loaded = health?.loaded_models || {}
  const active = Object.values(loaded)[0]?.model || '等待 worker'

  return <div className="shell">
    <aside className="rail"><div className="traffic"><i/><i/><i/></div><div className="brand"><span className="ember">✦</span><span>Kiln</span></div>
      <nav>{nav.map(([key, icon, label]) => <button className={tab === key ? 'nav active' : 'nav'} onClick={() => setTab(key)}><span>{icon}</span>{label}</button>)}</nav>
      <div className="rail-bottom"><span className="live"/>本地服务<br/><small>{settings.server.host}:{settings.server.port}</small></div>
    </aside>
    <main className="workspace">
      <header><div><h1>{nav.find(([key]) => key === tab)?.[2]}</h1><p>{active}</p></div><div className="header-status"><span className="status-dot"/> {health ? '在线' : '连接中'}<button className="quiet" onClick={refresh}>刷新</button></div></header>
      {tab === 'chat' && <AssistantChat model={settings.models.agent}/>}
      {tab === 'embed' && <Embed settings={settings}/>}
      {tab === 'ocr' && <Ocr/>}
      {tab === 'settings' && <SettingsPanel settings={settings} onSaved={setSettings}/>}
    </main>
  </div>
}

function createKilnAdapter(model: string): ChatModelAdapter {
  return {
    async *run({ messages, abortSignal }) {
      const payload = messages.map((message) => ({
        role: message.role,
        content: message.content.filter((part) => part.type === 'text').map((part) => part.text).join('\n'),
      }))
      const response = await fetch('/ui/api/chat', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: abortSignal,
        body: JSON.stringify({ model, messages: payload, temperature: .6, stream: true }),
      })
      if (!response.ok || !response.body) throw new Error(await response.text())
      const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '', fullText = ''
      while (true) {
        const { value, done } = await reader.read(); if (done) break
        buffer += decoder.decode(value, { stream: true }); const events = buffer.split('\n\n'); buffer = events.pop() || ''
        for (const event of events) for (const line of event.split('\n')) {
          if (!line.startsWith('data: ')) continue
          const data = line.slice(6); if (data === '[DONE]') continue
          try { fullText += JSON.parse(data).choices?.[0]?.delta?.content || ''; if (fullText) yield { content: [{ type: 'text', text: fullText }] } } catch { /* ignore incomplete SSE frames */ }
        }
      }
      if (!fullText) yield { content: [{ type: 'text' as const, text: '模型没有返回可显示的内容。' }] }
    },
  }
}

function UserMessage() {
  return <MessagePrimitive.Root className="message user"><div className="avatar">你</div><div className="message-body"><div className="role">你</div><div className="content"><MessagePrimitive.Content/></div><ActionBarPrimitive.Root className="message-actions"><ActionBarPrimitive.Edit>编辑</ActionBarPrimitive.Edit></ActionBarPrimitive.Root></div></MessagePrimitive.Root>
}
function AssistantMessage() {
  return <MessagePrimitive.Root className="message"><div className="avatar assistant-avatar">K</div><div className="message-body"><div className="role">Kiln</div><div className="content"><MessagePrimitive.Content/></div><ActionBarPrimitive.Root className="message-actions"><ActionBarPrimitive.Copy>复制</ActionBarPrimitive.Copy><ActionBarPrimitive.Reload>重新生成</ActionBarPrimitive.Reload></ActionBarPrimitive.Root></div></MessagePrimitive.Root>
}
function AssistantChat({ model }: { model: string }) {
  const adapter = useMemo(() => createKilnAdapter(model), [model]); const runtime = useLocalRuntime(adapter)
  return <AssistantRuntimeProvider runtime={runtime}><section className="chat-view"><ThreadPrimitive.Root className="assistant-thread"><ThreadPrimitive.Viewport className="conversation"><ThreadPrimitive.Empty><div className="welcome"><span className="ember">✦</span><h2>本地智能，随时开炉。</h2><p>支持流式对话、取消、编辑与重新生成。</p></div></ThreadPrimitive.Empty><ThreadPrimitive.Messages components={{ UserMessage, AssistantMessage }}/><ThreadPrimitive.ViewportFooter className="composer-wrap"><ComposerPrimitive.Root className="composer"><ComposerPrimitive.Input placeholder="问 Kiln 任何事…" autoFocus/><ComposerPrimitive.Cancel>停止</ComposerPrimitive.Cancel><ComposerPrimitive.Send>发送</ComposerPrimitive.Send></ComposerPrimitive.Root></ThreadPrimitive.ViewportFooter></ThreadPrimitive.Viewport></ThreadPrimitive.Root><div className="chat-tools"><span>assistant-ui runtime · 本地模型</span></div></section></AssistantRuntimeProvider>
}

function Embed({ settings }: { settings: Settings }) {
  const [input, setInput] = useState(''); const [result, setResult] = useState<number[] | null>(null); const [busy, setBusy] = useState(false)
  const run = async (e: FormEvent<HTMLFormElement>) => { e.preventDefault(); if (!input.trim()) return; setBusy(true); try { const data = await api<{ data: Array<{ embedding: number[] }> }>('embeddings', { method: 'POST', body: JSON.stringify({ model: settings.models.embedding, input }) }); setResult(data.data[0].embedding) } finally { setBusy(false) } }
  const download = () => { if (!result) return; const url = URL.createObjectURL(new Blob([JSON.stringify(result)], { type: 'application/json' })); Object.assign(document.createElement('a'), { href: url, download: 'kiln-embedding.json' }).click(); URL.revokeObjectURL(url) }
  return <section className="page"><div className="intro"><span>向量工作台</span><h2>把文本变成可检索的语义坐标。</h2><p>{settings.models.embedding}</p></div><form className="stack" onSubmit={run}><textarea rows={8} value={input} onInput={e => setInput((e.target as HTMLTextAreaElement).value)} placeholder="粘贴需要向量化的内容"/><button disabled={busy}>{busy ? '生成中…' : '生成向量'}</button></form>{result && <div className="result-card"><div><strong>{result.length.toLocaleString()} 维</strong><span>已生成</span></div><button className="quiet" onClick={download}>下载 JSON</button><pre>{JSON.stringify(result.slice(0, 24), null, 2)}</pre></div>}</section>
}

function MarkdownPreview({ source }: { source: string }) {
  if (!source.trim()) return <div className="preview-empty">没有可显示的 Markdown，仍可查看版面检测图或下载产物。</div>
  return <article className="markdown-preview">{source.split(/\n{2,}/).map((block, index) => {
    const lines = block.trim().split('\n')
    if (lines[0].startsWith('# ')) return <h2 key={index}>{lines[0].slice(2)}</h2>
    if (lines[0].startsWith('## ')) return <h3 key={index}>{lines[0].slice(3)}</h3>
    if (lines.every(line => /^[-*] /.test(line))) return <ul key={index}>{lines.map(line => <li>{line.slice(2)}</li>)}</ul>
    if (lines.every(line => /^\d+\. /.test(line))) return <ol key={index}>{lines.map(line => <li>{line.replace(/^\d+\. /, '')}</li>)}</ol>
    return <p key={index}>{lines.join('\n')}</p>
  })}</article>
}

function Ocr() {
  const [file, setFile] = useState<File | null>(null); const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ task: string; files: string[]; markdown: string } | null>(null)
  const [preview, setPreview] = useState<'result' | 'layout' | 'raw'>('result'); const input = useRef<HTMLInputElement>(null)
  const run = async (e: FormEvent<HTMLFormElement>) => { e.preventDefault(); if (!file) return; setBusy(true); const body = new FormData(); body.append('file', file); try { setResult(await api('ocr', { method: 'POST', body }) as { task: string; files: string[]; markdown: string }); setPreview('result') } finally { setBusy(false) } }
  const layout = result?.files.find(name => /_layout_det_res\.(png|jpe?g|webp)$/i.test(name))
  const fileUrl = (name: string) => `/ui/api/ocr/${result!.task}/${encodeURIComponent(name)}`
  return <section className="page"><div className="intro"><span>文档 OCR</span><h2>版面、阅读顺序和内容，一次解析。</h2><p>PDF、PNG、JPG、WEBP、BMP、TIFF，最大 100 MiB。</p></div><form onSubmit={run}><button type="button" className={`dropzone ${file ? 'chosen' : ''}`} onClick={() => input.current?.click()}><input ref={input} type="file" hidden accept=".pdf,image/*" onChange={e => setFile((e.target as HTMLInputElement).files?.[0] || null)}/><span className="upload-icon">↑</span><b>{file ? file.name : '选择文档或拖入这里'}</b><small>{file ? `${(file.size / 1024 / 1024).toFixed(1)} MiB` : '首次使用可能需要加载 OCR 模型'}</small></button><button disabled={!file || busy}>{busy ? '正在解析…' : '开始解析'}</button></form>{result && <div className="ocr-result"><div className="output-head"><div><strong>解析完成</strong><span>{result.files.length} 个产物</span></div><div className="downloads">{result.files.map(name => <a href={fileUrl(name)}>下载 {name}</a>)}</div></div><div className="preview-tabs"><button className={preview === 'result' ? 'selected' : ''} onClick={() => setPreview('result')}>内容预览</button>{layout && <button className={preview === 'layout' ? 'selected' : ''} onClick={() => setPreview('layout')}>版面标注</button>}<button className={preview === 'raw' ? 'selected' : ''} onClick={() => setPreview('raw')}>原始 Markdown</button></div>{preview === 'result' && <MarkdownPreview source={result.markdown}/>} {preview === 'layout' && layout && <figure className="layout-preview"><img src={fileUrl(layout)} alt="OCR layout detection result"/><figcaption>蓝框表示 PaddleOCR 检测到的版面区域。</figcaption></figure>} {preview === 'raw' && <pre>{result.markdown || '未生成 Markdown'}</pre>}</div>}</section>
}

function SettingsPanel({ settings, onSaved }: { settings: Settings; onSaved: (settings: Settings) => void }) {
  const [draft, setDraft] = useState(settings); const [saved, setSaved] = useState(false); const [busy, setBusy] = useState(false)
  useEffect(() => setDraft(settings), [settings]); const update = (group: 'models' | 'runtime', key: string, value: string | number | boolean) => setDraft({ ...draft, [group]: { ...draft[group], [key]: value } })
  const save = async (e: FormEvent<HTMLFormElement>) => { e.preventDefault(); setBusy(true); try { const response = await api<{ settings: Settings }>('settings', { method: 'PUT', body: JSON.stringify({ models: draft.models, runtime: draft.runtime }) }); onSaved(response.settings); setDraft(response.settings); setSaved(true) } finally { setBusy(false) } }
  const restart = async () => { await api('restart', { method: 'POST' }); setTimeout(() => location.reload(), 6000) }
  const field = (group: 'models' | 'runtime', key: string, label: string, type = 'text') => <label className="field"><span>{label}</span><input type={type} value={String(draft[group][key])} onInput={e => update(group, key, type === 'number' ? Number((e.target as HTMLInputElement).value) : (e.target as HTMLInputElement).value)}/></label>
  return <section className="page settings-page"><div className="intro"><span>运行设置</span><h2>配置模型，不碰密钥。</h2><p>保存写入 <code>~/.config/kiln/config.toml</code>，应用后重启 worker。</p></div><form className="settings-form" onSubmit={save}><h3>模型</h3><div className="form-grid">{field('models', 'agent', 'Agent 模型')}{field('models', 'draft', 'Draft 模型，留空关闭')}{field('models', 'embedding', 'Embedding 模型')}{field('models', 'ocr', 'OCR VLM 模型')}</div><h3>运行参数</h3><div className="form-grid">{field('runtime', 'draft_kind', 'Draft 类型')}{field('runtime', 'draft_block_size', 'Draft block size', 'number')}{field('runtime', 'kv_bits', 'KV bits', 'number')}{field('runtime', 'quantized_kv_start', '量化 KV 起点', 'number')}{field('runtime', 'max_kv_size', '最大 KV tokens', 'number')}{field('runtime', 'max_tokens', '最大输出 tokens', 'number')}{field('runtime', 'prefill_step_size', 'Prefill step size', 'number')}{field('runtime', 'vision_cache_size', 'Vision cache size', 'number')}{field('runtime', 'max_num_seqs', '最大并发序列', 'number')}</div><label className="toggle"><input type="checkbox" checked={Boolean(draft.runtime.enable_thinking)} onChange={e => update('runtime', 'enable_thinking', (e.target as HTMLInputElement).checked)}/><span>默认启用 thinking</span></label><div className="settings-actions"><button disabled={busy}>{busy ? '保存中…' : '保存设置'}</button>{saved && <button className="apply" type="button" onClick={restart}>应用并重启</button>}</div></form></section>
}

createRoot(document.getElementById('app')!).render(<App/>)
