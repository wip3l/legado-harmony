export interface AuthBody { authorizationCode?: string; }
export interface RedeemBody { requestId?: string; expectedPricePoints?: number; expectedValidDays?: number; }
export interface TtsRedeemBody { requestId?: string; }
export interface TtsSynthesizeBody { requestId?: string; voiceId?: string; text?: string; speed?: number; pitch?: number; volume?: number; timed?: boolean; transport?: string; }
export interface IapBody { purchaseData?: string; }
export interface ProfileBody { displayName?: string; avatarBase64?: string; removeAvatar?: boolean; }
