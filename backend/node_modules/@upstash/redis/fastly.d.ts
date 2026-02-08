import { R as RedisOptions, a as RequesterConfig, b as Redis$1 } from './zmscore-BjNXmrug.js';
export { A as AppendCommand, B as BitCountCommand, f as BitOpCommand, g as BitPosCommand, h as ClientSetInfoAttribute, C as ClientSetInfoCommand, i as CopyCommand, D as DBSizeCommand, k as DecrByCommand, j as DecrCommand, l as DelCommand, E as EchoCommand, n as EvalCommand, m as EvalROCommand, p as EvalshaCommand, o as EvalshaROCommand, q as ExistsCommand, t as ExpireAtCommand, r as ExpireCommand, s as ExpireOption, F as FlushAllCommand, u as FlushDBCommand, G as GeoAddCommand, v as GeoAddCommandOptions, x as GeoDistCommand, y as GeoHashCommand, w as GeoMember, z as GeoPosCommand, I as GeoSearchCommand, J as GeoSearchStoreCommand, L as GetBitCommand, K as GetCommand, M as GetDelCommand, N as GetExCommand, O as GetRangeCommand, Q as GetSetCommand, S as HDelCommand, T as HExistsCommand, W as HExpireAtCommand, V as HExpireCommand, X as HExpireTimeCommand, a3 as HGetAllCommand, a2 as HGetCommand, a4 as HGetDelCommand, a5 as HGetExCommand, a6 as HIncrByCommand, a7 as HIncrByFloatCommand, a8 as HKeysCommand, a9 as HLenCommand, aa as HMGetCommand, ab as HMSetCommand, _ as HPExpireAtCommand, Z as HPExpireCommand, $ as HPExpireTimeCommand, a0 as HPTtlCommand, a1 as HPersistCommand, ac as HRandFieldCommand, ad as HScanCommand, ae as HSetCommand, af as HSetExCommand, ag as HSetNXCommand, ah as HStrLenCommand, Y as HTtlCommand, ai as HValsCommand, ak as IncrByCommand, al as IncrByFloatCommand, aj as IncrCommand, am as JsonArrAppendCommand, an as JsonArrIndexCommand, ao as JsonArrInsertCommand, ap as JsonArrLenCommand, aq as JsonArrPopCommand, ar as JsonArrTrimCommand, as as JsonClearCommand, at as JsonDelCommand, au as JsonForgetCommand, av as JsonGetCommand, ax as JsonMGetCommand, aw as JsonMergeCommand, ay as JsonNumIncrByCommand, az as JsonNumMultByCommand, aA as JsonObjKeysCommand, aB as JsonObjLenCommand, aC as JsonRespCommand, aD as JsonSetCommand, aE as JsonStrAppendCommand, aF as JsonStrLenCommand, aG as JsonToggleCommand, aH as JsonTypeCommand, aI as KeysCommand, aJ as LIndexCommand, aK as LInsertCommand, aL as LLenCommand, aM as LMoveCommand, aN as LPopCommand, aO as LPushCommand, aP as LPushXCommand, aQ as LRangeCommand, aR as LRemCommand, aS as LSetCommand, aT as LTrimCommand, aU as MGetCommand, aV as MSetCommand, aW as MSetNXCommand, aZ as PExpireAtCommand, aY as PExpireCommand, a$ as PSetEXCommand, b0 as PTtlCommand, aX as PersistCommand, a_ as PingCommand, P as Pipeline, b1 as PublishCommand, b5 as RPopCommand, b6 as RPushCommand, b7 as RPushXCommand, b2 as RandomKeyCommand, b3 as RenameCommand, b4 as RenameNXCommand, c as Requester, b8 as SAddCommand, bb as SCardCommand, bf as SDiffCommand, bg as SDiffStoreCommand, bn as SInterCommand, bo as SInterStoreCommand, bp as SIsMemberCommand, br as SMIsMemberCommand, bq as SMembersCommand, bs as SMoveCommand, bt as SPopCommand, bu as SRandMemberCommand, bv as SRemCommand, bw as SScanCommand, by as SUnionCommand, bz as SUnionStoreCommand, b9 as ScanCommand, ba as ScanCommandOptions, bK as ScoreMember, bc as ScriptExistsCommand, bd as ScriptFlushCommand, be as ScriptLoadCommand, bj as SetBitCommand, bh as SetCommand, bi as SetCommandOptions, bk as SetExCommand, bl as SetNxCommand, bm as SetRangeCommand, bx as StrLenCommand, bA as TimeCommand, bB as TouchCommand, bC as TtlCommand, bD as Type, bE as TypeCommand, bF as UnlinkCommand, U as UpstashRequest, d as UpstashResponse, bH as XAckDelCommand, bG as XAddCommand, bI as XDelExCommand, bJ as XRangeCommand, bM as ZAddCommand, bL as ZAddCommandOptions, bN as ZCardCommand, bO as ZCountCommand, bP as ZDiffStoreCommand, bQ as ZIncrByCommand, bR as ZInterStoreCommand, bS as ZInterStoreCommandOptions, bT as ZLexCountCommand, bU as ZMScoreCommand, bV as ZPopMaxCommand, bW as ZPopMinCommand, bX as ZRangeCommand, bY as ZRangeCommandOptions, bZ as ZRankCommand, b_ as ZRemCommand, b$ as ZRemRangeByLexCommand, c0 as ZRemRangeByRankCommand, c1 as ZRemRangeByScoreCommand, c2 as ZRevRankCommand, c3 as ZScanCommand, c4 as ZScoreCommand, c5 as ZUnionCommand, c6 as ZUnionCommandOptions, c7 as ZUnionStoreCommand, c8 as ZUnionStoreCommandOptions, e as errors } from './zmscore-BjNXmrug.js';

/**
 * Connection credentials for upstash redis.
 * Get them from https://console.upstash.com/redis/<uuid>
 */
type RedisConfigFastly = {
    /**
     * UPSTASH_REDIS_REST_URL
     */
    url: string | undefined;
    /**
     * UPSTASH_REDIS_REST_TOKEN
     */
    token: string | undefined;
    /**
     * A Request can be forwarded to any backend defined on your service. Backends
     * can be created via the Fastly CLI, API, or web interface, and are
     * referenced by name.
     */
    backend: string;
    keepAlive?: boolean;
    /**
     * When this flag is enabled, any subsequent commands issued by this client are guaranteed to observe the effects of all earlier writes submitted by the same client.
     */
    readYourWrites?: boolean;
} & RedisOptions & RequesterConfig;
/**
 * Serverless redis client for upstash.
 */
declare class Redis extends Redis$1 {
    /**
     * Create a new redis client
     *
     * @example
     * ```typescript
     *    const redis = new Redis({
     *        url: "<UPSTASH_REDIS_REST_URL>",
     *        token: "<UPSTASH_REDIS_REST_TOKEN>",
     *        backend: "upstash-db",
     *    });
     * ```
     */
    constructor(config: RedisConfigFastly);
}

export { Redis, type RedisConfigFastly };
