import React, { useEffect, useState } from "react";
import { ProjectForm } from "./forms/ProjectForm";

type Project = {
  id: string;
  name: string;
  ownerEmail: string;
};

export function AdminApp(): React.JSX.Element {
  const [projects, setProjects] = useState<Project[]>([]);

  useEffect(() => {
    fetch("/api/projects")
      .then((response) => response.json())
      .then((data: Project[]) => setProjects(data));
  }, []);

  return (
    <main>
      <h1>Projects</h1>
      <ProjectForm onCreated={(project) => setProjects([...projects, project])} />
      <ul>
        {projects.map((project) => (
          <li key={project.id}>{project.name}</li>
        ))}
      </ul>
    </main>
  );
}
