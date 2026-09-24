export interface RoleMatrixProps {
  roles: Role[]
  assignedEntity: string
  reviewMode: boolean
}

export interface Role {
  id: number
  name: string
  shortcode: string | null
}

interface NotExported {
  hidden: boolean
}

export type RoleList = Role[]

export type MaybeRoles = Role[] | null

export type AliasedRoleList = RoleList
