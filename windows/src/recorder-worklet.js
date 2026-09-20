class RecorderProcessor extends AudioWorkletProcessor {
  constructor() { super(); this.samples = []; this.energy = 0; this.meterSamples = 0; this.port.onmessage = e => { if (e.data === 'flush') { if (this.samples.length) this.port.postMessage(new Float32Array(this.samples)); this.samples = []; this.port.postMessage('flushed'); } }; }
  process(inputs) {
    const channels = inputs[0];
    if (channels?.length) {
      for (let i = 0; i < channels[0].length; i++) { let sum = 0; for (const channel of channels) sum += channel[i]; const value = Math.max(-1, Math.min(1, sum / channels.length)); this.samples.push(value); this.energy += value * value; this.meterSamples++; }
      if (this.meterSamples >= 640) { const rms = Math.sqrt(this.energy / this.meterSamples); const level = Math.max(0, Math.min(1, (Math.log10(Math.max(.001, rms)) + 3) / 2.2)); this.port.postMessage({ level }); this.energy = 0; this.meterSamples = 0; }
      if (this.samples.length >= 4096) { this.port.postMessage(new Float32Array(this.samples)); this.samples = []; }
    }
    return true;
  }
}
registerProcessor('babji-recorder', RecorderProcessor);
