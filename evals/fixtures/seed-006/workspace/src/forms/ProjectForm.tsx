import React, { FormEvent, useState } from "react";

type Project = {
  id: string;
  name: string;
  ownerEmail: string;
};

type Props = {
  onCreated(project: Project): void;
};

export function ProjectForm({ onCreated }: Props): React.JSX.Element {
  const [name, setName] = useState("");
  const [ownerEmail, setOwnerEmail] = useState("");

  function submit(event: FormEvent): void {
    event.preventDefault();
    onCreated({ id: crypto.randomUUID(), name, ownerEmail });
  }

  return (
    <form onSubmit={submit}>
      <label>
        Project name
        <input value={name} onChange={(event) => setName(event.target.value)} />
      </label>
      <label>
        Owner email
        <input value={ownerEmail} onChange={(event) => setOwnerEmail(event.target.value)} />
      </label>
      <button type="submit">Create project</button>
    </form>
  );
}
