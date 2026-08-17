#!/usr/bin/env python3
import argparse
import os
import re

parser = argparse.ArgumentParser()
parser.add_argument('--map-dir', required=True)
parser.add_argument('--stage', required=True)
args = parser.parse_args()

from isaacsim import SimulationApp
app = SimulationApp({'headless': True})

from pxr import Gf, Usd, UsdGeom, UsdPhysics
from isaacsim.asset.importer.urdf.impl import URDFImporter, URDFImporterConfig

def safe_name(value):
    return re.sub(r'[^A-Za-z0-9_]', '_', value)

def read_obj(path, stage, prim_path):
    points, counts, indices = [], [], []
    with open(path, encoding='utf-8', errors='replace') as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith('v '):
                points.append(Gf.Vec3f(*(float(v) for v in line.split()[1:4])))
            elif line.startswith('f '):
                face = [int(v.split('/')[0]) - 1 for v in line.split()[1:]]
                if len(face) >= 3:
                    counts.append(len(face))
                    indices.extend(face)
    if not points or not counts:
        raise RuntimeError(f'OBJ에 형상이 없습니다: {path}')
    mesh = UsdGeom.Mesh.Define(stage, prim_path)
    mesh.CreatePointsAttr(points)
    mesh.CreateFaceVertexCountsAttr(counts)
    mesh.CreateFaceVertexIndicesAttr(indices)
    mesh.CreateSubdivisionSchemeAttr('none')
    UsdPhysics.CollisionAPI.Apply(mesh.GetPrim())

def yaml_value(path, key, default=''):
    pattern = re.compile(r'^' + re.escape(key) + r':\s*(.*?)\s*(?:#.*)?$')
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            match = pattern.match(line)
            if match:
                return match.group(1).strip()
    return default

def ros_packages_for(urdf_path):
    with open(urdf_path, encoding='utf-8') as handle:
        packages = sorted(set(re.findall(r'package://([^/]+)/', handle.read())))
    prefixes = [p for p in os.environ.get('AMENT_PREFIX_PATH', '').split(':') if p]
    resolved = []
    for package in packages:
        for prefix in prefixes:
            path = os.path.join(prefix, 'share', package)
            if os.path.isdir(path):
                resolved.append({'name': package, 'path': path})
                break
        else:
            raise RuntimeError(f'URDF package를 찾지 못했습니다: {package}')
    return resolved

stage_path = os.path.abspath(args.stage)
os.makedirs(os.path.dirname(stage_path), exist_ok=True)
stage = Usd.Stage.CreateNew(stage_path)
world = UsdGeom.Xform.Define(stage, '/World')
stage.SetDefaultPrim(world.GetPrim())
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
UsdGeom.SetStageMetersPerUnit(stage, 1.0)
UsdPhysics.Scene.Define(stage, '/World/PhysicsScene')

mesh_dir = os.path.join(args.map_dir, 'generated_models', 'project1-ver2_L1', 'meshes')
for name in ('floor_1.obj', 'wall_1.obj'):
    source = os.path.join(mesh_dir, name)
    if not os.path.isfile(source):
        raise RuntimeError(f'Gazebo 건물 메시가 없습니다: {source}')
    read_obj(source, stage, '/World/Environment/' + safe_name(name))

robots_dir = os.path.join(args.map_dir, 'robots')
urdf_dir = os.path.join(args.map_dir, 'isaac', 'robots')
asset_dir = os.path.join(args.map_dir, 'isaac', 'assets')
os.makedirs(asset_dir, exist_ok=True)
if os.path.isdir(urdf_dir):
    for filename in sorted(os.listdir(urdf_dir)):
        if not filename.endswith('.urdf'):
            continue
        robot_id = filename[:-5]
        urdf = os.path.join(urdf_dir, filename)
        config = URDFImporterConfig()
        config.urdf_path = urdf
        config.usd_path = os.path.join(asset_dir, robot_id)
        config.ros_package_paths = ros_packages_for(urdf)
        config.fix_base = False
        config.make_default_prim = True
        output = URDFImporter(config).import_urdf()
        if not output or not os.path.isfile(output):
            raise RuntimeError(f'URDF 변환 실패: {urdf}')
        root = UsdGeom.Xform.Define(stage, '/World/Robots/' + safe_name(robot_id))
        root.GetPrim().GetReferences().AddReference(output)
        meta = os.path.join(robots_dir, robot_id, 'robot.yaml')
        x = float(yaml_value(meta, 'spawn_x', '0') or 0)
        y = float(yaml_value(meta, 'spawn_y', '0') or 0)
        heading = float(yaml_value(meta, 'spawn_heading', '0') or 0)
        transform = UsdGeom.Xformable(root)
        transform.AddTranslateOp().Set(Gf.Vec3d(x, y, 0.0))
        transform.AddRotateZOp().Set(heading * 180.0 / 3.141592653589793)

stage.GetRootLayer().Save()
print(f'Isaac USD 생성 완료: {stage_path}')
app.close()
