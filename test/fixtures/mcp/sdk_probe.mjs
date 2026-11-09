// 使用外部安装的官方 SDK 验证真实协议交互，不向仓库引入 Node 运行依赖。
const { Client, StreamableHTTPClientTransport, SSEClientTransport } = await import(process.env.ANYDECK_MCP_SDK);
const port = process.argv[2];
for (const mode of ['auto', 'legacy']) {
  await Promise.all(['android', 'harmony', 'ios'].map(async platform => {
    const client = new Client({ name: `anydeck-probe-${platform}`, version: '1' }, { versionNegotiation: { mode } });
    try {
      console.log(`connecting ${mode}/${platform}`);
      await client.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp/${platform}`), {
        requestInit: { headers: { Authorization: `Bearer ${platform}-test` } },
      }));
      console.log(`connected ${mode}/${platform}`);
      const tools = await client.listTools();
      if (tools.tools.length !== 1 || tools.tools[0].name !== `${platform}_probe`) throw new Error('Tool isolation failed');
      const result = await client.callTool({ name: `${platform}_probe`, arguments: { deviceId: platform } });
      if (result.isError || result.structuredContent?.platform !== platform) throw new Error('Call result mismatch');
    } finally { await client.close(); }
  }));
}
console.log('connecting SSE');
const legacy = new Client({name: 'sse-probe', version: '1'});
try {
  await legacy.connect(new SSEClientTransport(new URL(`http://127.0.0.1:${port}/sse`)));
  console.log('connected SSE');
  const result = await legacy.listTools();
  if (result.tools.length !== 3) throw new Error('Legacy list failed');
} finally { await legacy.close(); }
console.log('PASS: 3 platforms × modern/legacy Streamable HTTP + legacy SSE');
