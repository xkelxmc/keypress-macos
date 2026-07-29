const sampleRate = 48_000;
const duration = 4.8;
const sampleCount = Math.floor(sampleRate * duration);
const samples = new Float64Array(sampleCount);

let randomState = 0x4b455950;

function random() {
  randomState = (1_664_525 * randomState + 1_013_904_223) >>> 0;
  return randomState / 0xffff_ffff;
}

function smoothEnvelope(time: number, start: number, attack: number, release: number) {
  if (time < start || time > start + attack + release) return 0;
  if (time < start + attack) return (time - start) / attack;
  const progress = (time - start - attack) / release;
  return Math.pow(1 - progress, 1.7);
}

function addTone(
  frequency: number,
  start: number,
  attack: number,
  release: number,
  gain: number,
) {
  for (let index = Math.floor(start * sampleRate); index < sampleCount; index += 1) {
    const time = index / sampleRate;
    const envelope = smoothEnvelope(time, start, attack, release);
    if (envelope <= 0) break;
    const phase = 2 * Math.PI * frequency * (time - start);
    const body = Math.sin(phase) + 0.22 * Math.sin(phase * 2) + 0.08 * Math.sin(phase * 3);
    samples[index] += body * envelope * gain;
  }
}

function addSwitch(start: number, pitch: number, gain: number) {
  let filteredNoise = 0;
  const firstSample = Math.floor(start * sampleRate);
  const length = Math.floor(0.13 * sampleRate);

  for (let offset = 0; offset < length; offset += 1) {
    const index = firstSample + offset;
    if (index >= sampleCount) break;
    const time = offset / sampleRate;
    const envelope = Math.exp(-time * 52);
    filteredNoise = filteredNoise * 0.6 + (random() * 2 - 1) * 0.4;
    const impact = Math.sin(2 * Math.PI * pitch * time) * Math.exp(-time * 34);
    const tick = Math.sin(2 * Math.PI * pitch * 3.7 * time) * Math.exp(-time * 88);
    samples[index] += (filteredNoise * 0.42 + impact + tick * 0.3) * envelope * gain;
  }
}

addSwitch(0.62, 118, 0.8);
addSwitch(1.24, 136, 0.72);
addTone(146.83, 1.34, 0.38, 3.0, 0.16);
addTone(220, 1.42, 0.44, 2.86, 0.105);
addTone(293.66, 1.52, 0.5, 2.68, 0.075);
addTone(587.33, 3.05, 0.08, 1.25, 0.065);
addTone(880, 3.12, 0.06, 0.92, 0.035);

const peak = samples.reduce(
  (currentPeak, sample) => Math.max(currentPeak, Math.abs(sample)),
  0,
);
const normalization = 0.82 / Math.max(peak, 0.001);

const dataSize = sampleCount * 2;
const buffer = Buffer.alloc(44 + dataSize);
buffer.write("RIFF", 0);
buffer.writeUInt32LE(36 + dataSize, 4);
buffer.write("WAVE", 8);
buffer.write("fmt ", 12);
buffer.writeUInt32LE(16, 16);
buffer.writeUInt16LE(1, 20);
buffer.writeUInt16LE(1, 22);
buffer.writeUInt32LE(sampleRate, 24);
buffer.writeUInt32LE(sampleRate * 2, 28);
buffer.writeUInt16LE(2, 32);
buffer.writeUInt16LE(16, 34);
buffer.write("data", 36);
buffer.writeUInt32LE(dataSize, 40);

for (let index = 0; index < sampleCount; index += 1) {
  const softened = Math.tanh(samples[index] * normalization * 1.12) / Math.tanh(1.12);
  buffer.writeInt16LE(Math.round(softened * 32_767), 44 + index * 2);
}

await Bun.write("Sources/Keypress/Resources/onboarding-ceremony.wav", buffer);
