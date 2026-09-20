// Runs ONNX in a utility process: model work never blocks the UI or hotkeys.
const port = process.parentPort;
let transcriber, loading, chain = Promise.resolve();
const send = value => port.postMessage(value);
async function load() {
  if (transcriber) return transcriber;
  if (!loading) loading = (async () => {
    const { pipeline, env } = await import('@huggingface/transformers');
    env.cacheDir = process.env.BABJI_MODEL_CACHE;
    env.allowLocalModels = false;
    transcriber = await pipeline('automatic-speech-recognition', 'onnx-community/whisper-base', {
      dtype: 'q8', device: 'cpu',
      progress_callback: progress => send({ type: 'progress', progress }),
      session_options: { intraOpNumThreads: Math.max(1, Math.min(4, require('node:os').availableParallelism() - 1)) }
    });
    return transcriber;
  })().catch(error => { loading = null; throw error; });
  return loading;
}
port.on('message', ({ data }) => {
  chain = chain.then(async () => {
    try {
      const pipe = await load();
      if (data.action === 'load') { send({ id: data.id, result: true }); return; }
      const samples = new Float32Array(data.samples);
      let energy = 0; for (const s of samples) energy += s * s;
      if (Math.sqrt(energy / Math.max(1, samples.length)) < 0.001) { send({ id: data.id, result: { text: '', chunks: [] } }); return; }
      const result = await pipe(samples, { chunk_length_s: 30, stride_length_s: 5, return_timestamps: true, task: 'transcribe', ...(data.language === 'auto' ? {} : { language: data.language || 'english' }) });
      send({ id: data.id, result });
    } catch (error) { send({ id: data.id, error: error.message }); }
  });
});
