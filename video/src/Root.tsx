import { Composition } from "remotion";
import { LaunchVideo, DURATION_FRAMES, FPS } from "./LaunchVideo";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="LaunchVideo"
    component={LaunchVideo}
    durationInFrames={DURATION_FRAMES}
    fps={FPS}
    width={1920}
    height={1080}
  />
);
