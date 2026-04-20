import { GraphQLClient, gql } from "graphql-request";

export interface UnraidSnapshot {
  info: {
    os: { hostname: string; uptime: string; kernel: string };
    versions: { core: { unraid: string; api: string; kernel: string } };
  };
  array: {
    state: string;
    capacity: { kilobytes: { free: string; used: string; total: string } };
    parities: Array<{ name: string; status: string; temp: number | null }>;
    disks: Array<{ name: string; status: string; temp: number | null; numErrors: number }>;
    caches: Array<{ name: string; status: string; temp: number | null }>;
    parityCheckStatus: {
      progress: number | null;
      running: boolean | null;
      paused: boolean | null;
      errors: number | null;
    };
  };
  docker: {
    containers: Array<{
      id: string;
      names: string[];
      image: string;
      state: string;
      status: string;
      autoStart: boolean;
    }>;
  };
  notifications: {
    overview: {
      unread: { total: number; info: number; warning: number; alert: number };
    };
  };
  metrics: {
    cpu: {
      percentTotal: number;
      cpus: Array<{ percentTotal: number }>;
    };
    memory: { percentTotal: number; total: number; used: number };
  };
}

const SNAPSHOT_QUERY = gql`
  {
    info {
      os { hostname uptime kernel }
      versions { core { unraid api kernel } }
    }
    array {
      state
      capacity { kilobytes { free used total } }
      parities { name status temp }
      disks { name status temp numErrors }
      caches { name status temp }
      parityCheckStatus { progress running paused errors }
    }
    docker {
      containers { id names image state status autoStart }
    }
    notifications {
      overview { unread { total info warning alert } }
    }
    metrics {
      cpu { percentTotal cpus { percentTotal } }
      memory { percentTotal total used }
    }
  }
`;

export class UnraidClient {
  private client: GraphQLClient;

  constructor(url: string, apiKey: string) {
    this.client = new GraphQLClient(url, {
      headers: { "x-api-key": apiKey },
    });
  }

  async snapshot(): Promise<UnraidSnapshot> {
    return this.client.request<UnraidSnapshot>(SNAPSHOT_QUERY);
  }

  async listUnreadNotifications(limit = 50): Promise<UnraidNotification[]> {
    return this.listNotifications("UNREAD", limit, 0);
  }

  async listNotifications(
    type: "UNREAD" | "ARCHIVE",
    limit = 50,
    offset = 0,
  ): Promise<UnraidNotification[]> {
    const data = await this.client.request<{ notifications: { list: UnraidNotification[] } }>(
      LIST_NOTIFICATIONS_QUERY,
      { type, limit, offset },
    );
    return data.notifications.list;
  }

  async dockerStart(id: string): Promise<{ id: string; state: string; status: string }> {
    const data = await this.client.request<{ docker: { start: ContainerResult } }>(
      DOCKER_START_MUTATION,
      { id },
    );
    return data.docker.start;
  }

  async dockerStop(id: string): Promise<{ id: string; state: string; status: string }> {
    const data = await this.client.request<{ docker: { stop: ContainerResult } }>(
      DOCKER_STOP_MUTATION,
      { id },
    );
    return data.docker.stop;
  }

  async archiveNotification(id: string): Promise<unknown> {
    const data = await this.client.request<{ archiveNotification: unknown }>(
      ARCHIVE_NOTIFICATION_MUTATION,
      { id },
    );
    return data.archiveNotification;
  }

  async unarchiveNotifications(ids: string[]): Promise<unknown> {
    const data = await this.client.request<{ unarchiveNotifications: unknown }>(
      UNARCHIVE_NOTIFICATIONS_MUTATION,
      { ids },
    );
    return data.unarchiveNotifications;
  }

  async archiveAll(): Promise<unknown> {
    const data = await this.client.request<{ archiveAll: unknown }>(ARCHIVE_ALL_MUTATION);
    return data.archiveAll;
  }

  async parityPause(): Promise<unknown> {
    const data = await this.client.request<{ parityCheck: { pause: unknown } }>(PARITY_PAUSE_MUTATION);
    return data.parityCheck.pause;
  }

  async parityResume(): Promise<unknown> {
    const data = await this.client.request<{ parityCheck: { resume: unknown } }>(PARITY_RESUME_MUTATION);
    return data.parityCheck.resume;
  }

  async parityCancel(): Promise<unknown> {
    const data = await this.client.request<{ parityCheck: { cancel: unknown } }>(PARITY_CANCEL_MUTATION);
    return data.parityCheck.cancel;
  }
}

interface ContainerResult {
  id: string;
  state: string;
  status: string;
}

const DOCKER_START_MUTATION = gql`
  mutation DockerStart($id: PrefixedID!) {
    docker { start(id: $id) { id state status } }
  }
`;

const DOCKER_STOP_MUTATION = gql`
  mutation DockerStop($id: PrefixedID!) {
    docker { stop(id: $id) { id state status } }
  }
`;

const ARCHIVE_NOTIFICATION_MUTATION = gql`
  mutation ArchiveNotification($id: PrefixedID!) {
    archiveNotification(id: $id) { id }
  }
`;

const UNARCHIVE_NOTIFICATIONS_MUTATION = gql`
  mutation UnarchiveNotifications($ids: [String!]!) {
    unarchiveNotifications(ids: $ids) { unread { total } }
  }
`;

const ARCHIVE_ALL_MUTATION = gql`
  mutation ArchiveAll { archiveAll { unread { total } } }
`;

const PARITY_PAUSE_MUTATION = gql`mutation { parityCheck { pause } }`;
const PARITY_RESUME_MUTATION = gql`mutation { parityCheck { resume } }`;
const PARITY_CANCEL_MUTATION = gql`mutation { parityCheck { cancel } }`;

export interface UnraidNotification {
  id: string;
  title: string;
  subject: string;
  description: string;
  importance: "INFO" | "WARNING" | "ALERT";
  link: string | null;
  type: "UNREAD" | "ARCHIVE";
  timestamp: string | null;
  formattedTimestamp: string | null;
}

const LIST_NOTIFICATIONS_QUERY = gql`
  query ListNotifications($type: NotificationType!, $limit: Int!, $offset: Int!) {
    notifications {
      list(filter: { type: $type, offset: $offset, limit: $limit }) {
        id
        title
        subject
        description
        importance
        link
        type
        timestamp
        formattedTimestamp
      }
    }
  }
`;
