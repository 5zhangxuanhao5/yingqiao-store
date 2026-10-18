export interface WANPeerRoute {
 name: string; ips: string[]; online: boolean; connection: string;
}
export interface WANRouteSnapshot {
 state: string; peers?: WANPeerRoute[];
 snapshotReady?: boolean; snapshotAgeMs?: number; snapshotSequence?: number;
}
export interface WANRouteEvidenceState {
 direct: boolean; ageMs: number; sequence: number; reason: string;
}

// This is a choice based on an existing observation, never a reachability or
// identity grant. The paired TLS/certificate handshake still authenticates Mac.
export class DirectWANRoute {
 private direct: boolean = false;
 private target: string = '';
 private epoch: number = -1;
 private observedAt: number = -1;
 private sourceAgeMs: number = -1;
 private sequence: number = 0;
 private reason: string = 'missing';
 private settlingEpoch: number = -1;
 private sampleNotBefore: number = -1;
 clear(reason: string = 'invalidated'): void {
  this.direct = false;this.target = '';this.epoch = -1;this.observedAt = -1;
  this.sourceAgeMs = -1;this.sequence = 0;this.reason = reason;
 }
 // EdgelinkSetNetwork injects its change asynchronously. An observation must
 // be newer than the old UDP address trust window (6.5 s in current Go runtime).
 // No timer or foreground delay is added; other observations retain route 3.
 networkChanged(epoch: number, now: number): void {
  this.clear('network_settling');this.settlingEpoch = epoch;
  this.sampleNotBefore = Number.isFinite(now) && now >= 0 ? now + 8000 : Number.POSITIVE_INFINITY;
 }
 observe(snapshot: WANRouteSnapshot, target: string, epoch: number, platformReady: boolean, now: number): void {
  this.clear('not_direct');
  if (!platformReady || snapshot.state !== 'Running' || snapshot.snapshotReady !== true ||
   typeof snapshot.snapshotAgeMs !== 'number' || !Number.isFinite(snapshot.snapshotAgeMs) || snapshot.snapshotAgeMs < 0 || snapshot.snapshotAgeMs > 15000 ||
   typeof snapshot.snapshotSequence !== 'number' || !Number.isSafeInteger(snapshot.snapshotSequence) || snapshot.snapshotSequence <= 0 ||
   !Number.isSafeInteger(epoch) || epoch < 0 || !Number.isFinite(now) || now < 0 || !target || !Array.isArray(snapshot.peers)) { this.reason = 'unverified_snapshot';return; }
  if (epoch === this.settlingEpoch && now - snapshot.snapshotAgeMs < this.sampleNotBefore) { this.reason = 'network_settling';return; }
  const candidates = snapshot.peers.filter((peer: WANPeerRoute) => peer !== null && peer !== undefined && peer.name === 'edgelink-mac' && peer.online === true);
  if (candidates.length !== 1) { this.reason = 'ambiguous_or_missing_peer';return; }
  const peer = candidates[0];
  if (peer.connection !== 'direct' || !Array.isArray(peer.ips) || !peer.ips.includes(target)) { this.reason = 'not_direct_to_target';return; }
  this.direct = true;this.target = target;this.epoch = epoch;this.observedAt = now;
  this.sourceAgeMs = snapshot.snapshotAgeMs;this.sequence = snapshot.snapshotSequence;this.reason = 'confirmed_direct';
 }
 private fresh(target: string, epoch: number, platformReady: boolean, now: number): boolean {
  return this.direct && platformReady && target === this.target && epoch === this.epoch &&
   Number.isFinite(now) && now >= this.observedAt && this.sourceAgeMs + now - this.observedAt <= 15000;
 }
 choose(mode: string, requested: number, target: string, epoch: number, platformReady: boolean, now: number, diagnostic: boolean, noFallback: boolean, failedUDP: boolean): number {
  if (mode !== 'remote' || requested !== 3 || diagnostic || noFallback || failedUDP) { return requested; }
  return this.fresh(target, epoch, platformReady, now) ? 4 : requested;
 }
 state(target: string, epoch: number, platformReady: boolean, now: number): WANRouteEvidenceState {
  const age = this.observedAt >= 0 && now >= this.observedAt ? this.sourceAgeMs + now - this.observedAt : -1;
  return { direct: this.fresh(target, epoch, platformReady, now), ageMs: age, sequence: this.sequence, reason: this.reason };
 }
}
