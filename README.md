# ultrastar-model

Investigation and design for an ML system that generates synchronized UltraStar karaoke (`.txt`) files from arbitrary songs, including a YouTube-link-to-UltraStar workflow.

## Goal

Build a model-backed pipeline that takes a YouTube URL and outputs:

1. Separated vocal audio
2. Time-aligned lyrics
3. Per-note pitch and duration aligned to lyrics
4. A valid UltraStar `.txt` file usable in karaoke programs

## End-to-end system design

```text
YouTube URL
  -> audio download + normalization
  -> vocal separation
  -> ASR with timestamps
  -> forced alignment / word-phoneme timing refinement
  -> F0 (pitch) extraction on vocal track
  -> note segmentation + lyric-to-note alignment
  -> UltraStar token generation (BPM, GAP, notes, sentence markers)
  -> post-processing + format validation
  -> song.txt (+ optional cover/background/audio assets)
```

## Proposed model architecture

Use a hybrid approach (specialized models per subtask) instead of one monolithic network.

### 1) Vocal isolation
- **Model**: Demucs (HTDemucs) or equivalent source-separation model
- **Input**: full mix waveform
- **Output**: isolated vocal stem

### 2) Lyrics transcription
- **Model**: Whisper-large-v3 (fine-tuned for singing if available)
- **Input**: vocal stem
- **Output**: token/word timestamps + text hypothesis

### 3) Alignment refinement
- **Model**: CTC/attention forced aligner (e.g., MFA / wav2vec2 aligner)
- **Input**: vocal stem + transcript
- **Output**: refined word/phoneme boundaries

### 4) Melody / pitch tracking
- **Model**: CREPE or torchcrepe (frame-level F0)
- **Input**: vocal stem
- **Output**: time series of frequency + confidence

### 5) Note-event generation (core learnable module)
- **Model**: Transformer encoder-decoder over multimodal sequence
  - Encoder inputs: acoustic embeddings + F0 contour + aligned lyric timing
  - Decoder outputs: note events `(start_tick, duration_tick, pitch, lyric_piece, type)`
- **Losses**:
  - Event token cross-entropy
  - Pitch regression/classification loss
  - Duration loss
  - Alignment consistency loss (predicted note spans vs lyric boundaries)

### 6) UltraStar formatter
- Deterministic conversion from note events to UltraStar lines:
  - Headers (`#TITLE`, `#ARTIST`, `#BPM`, `#GAP`, ...)
  - Note rows (`: start duration pitch syllable`)
  - Sentence breaks (`-`) and end marker (`E`)

## Suitable datasets

Because no single dataset contains perfect UltraStar supervision, combine datasets by role:

1. **Source separation / vocals**
   - MUSDB18
   - DSD100

2. **Singing voice + melody / F0**
   - MIR-1K
   - iKala
   - MedleyDB (vocal stems/annotations where available)
   - TONAS / vocal melody corpora

3. **Lyrics + singing alignment**
   - DALI (large corpus with lyric timing)
   - Jamendo lyrics datasets (where licensing allows)
   - NUS Sung and similar aligned singing corpora

4. **UltraStar supervision**
   - Community UltraStar songs (license-filtered)
   - Build parser to convert existing `.txt` files into structured note events

5. **Weakly supervised web-scale data**
   - YouTube + lyrics pairs with pseudo-labeling (high-confidence only)

## Public dataset links and local pull script

This repository includes:

- `datasets/public_links.tsv`: dataset -> public link -> direct archive URL (if available) -> access mode
- `scripts/pull_datasets.sh`: helper script to download datasets that have direct archive links

### Usage

```bash
chmod +x /home/runner/work/ultrastar-model/ultrastar-model/scripts/pull_datasets.sh

# list all datasets and links
/home/runner/work/ultrastar-model/ultrastar-model/scripts/pull_datasets.sh --list

# download all datasets that expose direct archive URLs
/home/runner/work/ultrastar-model/ultrastar-model/scripts/pull_datasets.sh --all

# download a single dataset by manifest name
/home/runner/work/ultrastar-model/ultrastar-model/scripts/pull_datasets.sh --dataset DSD100
```

Datasets without `direct_archive_url` are intentionally marked as manual/license-gated and should be obtained from their public links according to their terms.

## Data preprocessing strategy

1. Normalize sample rate (e.g., 44.1kHz source, 16kHz ASR branch)
2. Run vocal separation; keep confidence score
3. Clean lyrics (punctuation, repeated choruses, multilingual handling)
4. Forced-align transcript to audio
5. Extract F0 and voicing probability
6. Convert to musical semitone space and quantize to MIDI-like pitch bins
7. Build training targets as note events and UltraStar ticks
8. Reject/weight low-confidence pseudo-labeled samples

## Training loop design

### Phase A: component pretraining
- Train or adopt best-available checkpoints for:
  - Separation
  - ASR
  - Pitch extraction
  - Alignment

### Phase B: note-event model supervised training
- Input batch:
  - acoustic embeddings
  - F0 sequence
  - lyric timing tokens
- Target:
  - UltraStar note-event sequence
- Optimization:
  - AdamW, warmup + cosine decay
  - Label smoothing for event tokens
  - Mixed precision
  - Gradient clipping

### Phase C: weak/self-training
- Generate pseudo UltraStar labels on unlabeled songs
- Keep only high-confidence segments (ASR confidence, pitch confidence, alignment score)
- Retrain with supervised + weighted pseudo-labeled mix

### Phase D: task-level fine-tuning
- Fine-tune on hand-corrected UltraStar songs for style consistency

## Evaluation protocol

Evaluate at component and end-to-end levels.

### Component metrics
- **ASR**: WER/CER on singing-specific benchmarks
- **Alignment**: median word boundary error (ms)
- **Pitch**: Raw Pitch Accuracy (RPA), Voicing F1
- **Segmentation**: note onset/offset F1 at tolerance windows

### UltraStar-structure metrics
- Header validity rate
- Parse success rate in UltraStar players
- Tick alignment error vs reference charts
- Pitch deviation in semitones
- Lyric-token coverage and ordering accuracy

### End-to-end karaoke usability
- Mean opinion score from singers/charters
- Manual edit distance (minutes of correction required per song)
- Real-time playback sync acceptance rate

## Inference from YouTube link

1. Fetch audio from URL
2. Run pipeline components sequentially
3. Decode note events
4. Emit `song.txt` in UltraStar format
5. Run strict validator:
   - valid headers
   - monotonically increasing note starts
   - legal pitch range
   - final `E` marker

## Practical baseline to implement first

For fastest path to working output:

1. Use pretrained Demucs + Whisper + torchcrepe
2. Implement deterministic note segmentation from F0 contour
3. Align lyric syllables to note spans heuristically
4. Export UltraStar and validate
5. Add learned Transformer decoder in second iteration

This baseline provides immediate usable files and creates training data for the stronger learned model.
