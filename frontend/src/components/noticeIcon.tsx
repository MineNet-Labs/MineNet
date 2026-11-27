import {
  IconAlertTriangle,
  IconBuildingBank,
  IconBuildingStore,
  IconCertificate,
  IconShieldCheck,
  IconTruck,
  IconWallet,
  type Icon as TablerIcon,
} from "@tabler/icons-react";
import type { NoticeKind } from "@/lib/data";

export const noticeIcon: Record<NoticeKind, TablerIcon> = {
  inspection: IconShieldCheck,
  licence: IconCertificate,
  offer: IconBuildingStore,
  custody: IconTruck,
  payment: IconWallet,
  finance: IconBuildingBank,
  alert: IconAlertTriangle,
};
